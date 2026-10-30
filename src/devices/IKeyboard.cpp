#include "IKeyboard.hpp"
#include "../defines.hpp"
#include "../config/ConfigManager.hpp"
#include "../managers/input/InputManager.hpp"
#include "../managers/SeatManager.hpp"
#include "../helpers/MiscFunctions.hpp"
#include "../errorOverlay/Overlay.hpp"
#include "../keybinds/Key.hpp"
#include <sys/mman.h>
#include <aquamarine/input/Input.hpp>
#include <hyprutils/string/VarList.hpp>
#include <cstring>
#include <functional>

using namespace Hyprutils::OS;
using namespace Hyprutils::String;

#define LED_COUNT 3

constexpr static std::array<const char*, 8> MODNAMES = {
    XKB_MOD_NAME_SHIFT, XKB_MOD_NAME_CAPS, XKB_MOD_NAME_CTRL, XKB_MOD_NAME_ALT, XKB_MOD_NAME_NUM, "Mod3", XKB_MOD_NAME_LOGO, "Mod5",
};

constexpr static std::array<const char*, 3> LEDNAMES = {XKB_LED_NAME_NUM, XKB_LED_NAME_CAPS, XKB_LED_NAME_SCROLL};

// The keymap compiled last and its rules. A laptop has several keyboard devices with the same rules (keyboard, power
// button, video bus, ...), and compiling a keymap takes about 6 ms on a Core 2. Keymaps are immutable and reference
// counted, so keyboards with the same rules share one. Cleared on every config reload, see clearKeymapCache().
static IKeyboard::SStringRuleNames lastKeymapRules;
static xkb_keymap*                 lastKeymap = nullptr;

static bool                        sameRules(const IKeyboard::SStringRuleNames& a, const IKeyboard::SStringRuleNames& b) {
    return a.layout == b.layout && a.model == b.model && a.variant == b.variant && a.options == b.options && a.rules == b.rules;
}

// The text and shm files of the keymaps serialized last, by compiled keymap. Serializing a keymap in both formats and
// writing the files takes about half a millisecond on a slow CPU, and it was done for every keyboard device and twice
// for every virtual keyboard an input method makes: fcitx5 makes one per focus change, with the keymap it got from the
// compositor. A cached keymap is referenced, so its address stays its own. Cleared with the keymap cache.
constexpr static size_t                                                 KEYMAP_FILES_CACHE = 4;
static std::vector<std::pair<xkb_keymap*, SP<IKeyboard::SKeymapFiles>>> keymapFilesCache;

static void                                                             clearKeymapFilesCache() {
    for (auto& [keymap, files] : keymapFilesCache)
        xkb_keymap_unref(keymap);
    keymapFilesCache.clear();
}

void IKeyboard::clearKeymapCache() {
    if (lastKeymap)
        xkb_keymap_unref(lastKeymap);

    lastKeymap = nullptr;

    clearKeymapFilesCache();
}

static bool writeKeymapFile(const std::string& text, CFileDescriptor& ro) {
    CFileDescriptor rw;
    if (!allocateSHMFilePair(text.length() + 1, rw, ro))
        return false;

    auto dest = mmap(nullptr, text.length() + 1, PROT_READ | PROT_WRITE, MAP_SHARED, rw.get(), 0);
    if (dest == MAP_FAILED) {
        ro.reset();
        return false;
    }

    memcpy(dest, text.c_str(), text.length() + 1);
    munmap(dest, text.length() + 1);
    ro.setFlags(ro.getFlags() | FD_CLOEXEC);
    return true;
}

SP<IKeyboard::SKeymapFiles> IKeyboard::filesForKeymap(xkb_keymap* keymap) {
    for (auto it = keymapFilesCache.begin(); it != keymapFilesCache.end(); ++it) {
        if (it->first != keymap)
            continue;

        auto files = it->second;
        keymapFilesCache.erase(it); // the one used last goes to the back
        keymapFilesCache.emplace_back(keymap, files);
        return files;
    }

    auto files = makeShared<SKeymapFiles>();
    auto text  = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V2);
    files->v2  = text ? text : "";
    free(text); // NOLINT(cppcoreguidelines-no-malloc,-warnings-as-errors)
    text      = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    files->v1 = text ? text : "";
    free(text); // NOLINT(cppcoreguidelines-no-malloc,-warnings-as-errors)
    files->hashV1 = std::hash<std::string>{}(files->v1);

    if (!writeKeymapFile(files->v2, files->fdV2) || !writeKeymapFile(files->v1, files->fdV1)) {
        Log::logger->log(Log::ERR, "IKeyboard: failed to allocate shm files for the keymap");
        return nullptr;
    }

    if (keymapFilesCache.size() >= KEYMAP_FILES_CACHE) {
        xkb_keymap_unref(keymapFilesCache.front().first);
        keymapFilesCache.erase(keymapFilesCache.begin());
    }
    keymapFilesCache.emplace_back(xkb_keymap_ref(keymap), files);
    return files;
}

xkb_keymap* IKeyboard::keymapForRules(const SStringRuleNames& rules) {
    if (lastKeymap && sameRules(rules, lastKeymapRules))
        return xkb_keymap_ref(lastKeymap);

    xkb_rule_names XKBRULES = {
        .rules = rules.rules.c_str(), .model = rules.model.c_str(), .layout = rules.layout.c_str(), .variant = rules.variant.c_str(), .options = rules.options.c_str()};
    const auto CONTEXT = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    const auto KEYMAP  = xkb_keymap_new_from_names2(CONTEXT, &XKBRULES, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);
    xkb_context_unref(CONTEXT);
    if (!KEYMAP)
        return nullptr;

    clearKeymapCache();
    lastKeymap      = xkb_keymap_ref(KEYMAP);
    lastKeymapRules = rules;
    return KEYMAP;
}

//
uint32_t IKeyboard::getCapabilities() {
    return HID_INPUT_CAPABILITY_KEYBOARD;
}

eHIDType IKeyboard::getType() {
    return HID_TYPE_KEYBOARD;
}

IKeyboard::~IKeyboard() {
    m_events.destroy.emit();

    clearManuallyAllocd();
}

void IKeyboard::clearManuallyAllocd() {
    if (m_xkbStaticState)
        xkb_state_unref(m_xkbStaticState);

    if (m_xkbState)
        xkb_state_unref(m_xkbState);

    if (m_xkbKeymap)
        xkb_keymap_unref(m_xkbKeymap);

    if (m_xkbSymState)
        xkb_state_unref(m_xkbSymState);

    m_xkbSymState    = nullptr;
    m_xkbKeymap      = nullptr;
    m_xkbState       = nullptr;
    m_xkbStaticState = nullptr;
    m_keymapFiles.reset();
}

void IKeyboard::setKeymap(const SStringRuleNames& rules) {
    if (m_keymapOverridden) {
        Log::logger->log(Log::DEBUG, "Ignoring setKeymap: keymap is overridden");
        return;
    }

    m_currentRules          = rules;
    xkb_rule_names XKBRULES = {
        .rules   = rules.rules.c_str(),
        .model   = rules.model.c_str(),
        .layout  = rules.layout.c_str(),
        .variant = rules.variant.c_str(),
        .options = rules.options.c_str(),
    };

    const auto CONTEXT = xkb_context_new(XKB_CONTEXT_NO_FLAGS);

    if (!CONTEXT) {
        Log::logger->log(Log::ERR, "setKeymap: CONTEXT null??");
        return;
    }

    clearManuallyAllocd();

    Log::logger->log(Log::DEBUG, "Attempting to create a keymap for layout {} with variant {} (rules: {}, model: {}, options: {})", rules.layout, rules.variant, rules.rules,
                     rules.model, rules.options);

    if (!m_xkbFilePath.empty()) {
        auto path = absolutePath(m_xkbFilePath, Config::mgr()->currentConfigPath());

        if (FILE* const KEYMAPFILE = fopen(path.c_str(), "r"); !KEYMAPFILE)
            Log::logger->log(Log::ERR, "Cannot open input:kb_file= file for reading");
        else {
            m_xkbKeymap = xkb_keymap_new_from_file(CONTEXT, KEYMAPFILE, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);
            fclose(KEYMAPFILE);
        }
    }

    if (!m_xkbKeymap && m_xkbFilePath.empty())
        m_xkbKeymap = keymapForRules(rules);

    if (!m_xkbKeymap) {
        m_xkbKeymap = xkb_keymap_new_from_names2(CONTEXT, &XKBRULES, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);
    }

    if (!m_xkbKeymap) {
        ErrorOverlay::overlay()->queueError(std::format("Invalid keyboard layout passed. ( rules: {}, model: {}, variant: {}, options: {}, layout: {} )", rules.rules, rules.model,
                                                        rules.variant, rules.options, rules.layout));

        Log::logger->log(Log::ERR, "Keyboard layout {} with variant {} (rules: {}, model: {}, options: {}) couldn't have been loaded.", rules.layout, rules.variant, rules.rules,
                         rules.model, rules.options);
        memset(&XKBRULES, 0, sizeof(XKBRULES));

        m_currentRules.rules   = "";
        m_currentRules.model   = "";
        m_currentRules.variant = "";
        m_currentRules.options = "";
        m_currentRules.layout  = "us";

        m_xkbKeymap = xkb_keymap_new_from_names2(CONTEXT, &XKBRULES, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);
    }

    updateXKBTranslationState(m_xkbKeymap);

    const auto NUMLOCKON = Config::mgr()->getDeviceInt(m_hlName, "numlock_by_default", "input:numlock_by_default");

    if (NUMLOCKON == 1) {
        // lock numlock
        const auto IDX = xkb_map_mod_get_index(m_xkbKeymap, XKB_MOD_NAME_NUM);

        if (IDX != XKB_MOD_INVALID)
            m_modifiersState.locked |= sc<uint32_t>(1) << IDX;

        // 0 to avoid mods getting stuck if depressed during reload
        updateModifiers(0, 0, m_modifiersState.locked, m_modifiersState.group);
    }

    for (size_t i = 0; i < std::min(LEDNAMES.size(), m_ledIndexes.size()); ++i) {
        m_ledIndexes[i] = xkb_map_led_get_index(m_xkbKeymap, LEDNAMES[i]);
        Log::logger->log(Log::DEBUG, "xkb: LED index {} (name {}) got index {}", i, LEDNAMES[i], m_ledIndexes[i]);
    }

    for (size_t i = 0; i < std::min(MODNAMES.size(), m_modIndexes.size()); ++i) {
        m_modIndexes[i] = xkb_map_mod_get_index(m_xkbKeymap, MODNAMES[i]);
        Log::logger->log(Log::DEBUG, "xkb: Mod index {} (name {}) got index {}", i, MODNAMES[i], m_modIndexes[i]);
    }

    updateKeymapFD();

    xkb_context_unref(CONTEXT);

    g_pSeatManager->updateActiveKeyboardData();
}

void IKeyboard::updateKeymapFD() {
    Log::logger->log(Log::DEBUG, "Updating keymap fd for keyboard {}", m_deviceName);

    m_keymapFiles.reset();

    if (!m_xkbKeymap)
        return;

    m_keymapFiles = filesForKeymap(m_xkbKeymap);

    if (m_keymapFiles)
        Log::logger->log(Log::DEBUG, "Updated keymap fd to {}, keymap V1 to: {}", m_keymapFiles->fdV2.get(), m_keymapFiles->fdV1.get());
}

void IKeyboard::updateXKBTranslationState(xkb_keymap* const keymap) {

    if (m_xkbStaticState)
        xkb_state_unref(m_xkbStaticState);

    if (m_xkbState)
        xkb_state_unref(m_xkbState);

    if (m_xkbSymState)
        xkb_state_unref(m_xkbSymState);

    m_xkbState       = nullptr;
    m_xkbStaticState = nullptr;
    m_xkbSymState    = nullptr;

    if (keymap) {
        Log::logger->log(Log::DEBUG, "Updating keyboard {:x}'s translation state from a provided keymap", rc<uintptr_t>(this));
        m_xkbStaticState = xkb_state_new(keymap);
        m_xkbState       = xkb_state_new(keymap);
        m_xkbSymState    = xkb_state_new(keymap);
        return;
    }

    const auto KEYMAP     = m_xkbKeymap;
    const auto STATE      = m_xkbState;
    const auto LAYOUTSNUM = xkb_keymap_num_layouts(KEYMAP);

    const auto PCONTEXT = xkb_context_new(XKB_CONTEXT_NO_FLAGS);

    for (uint32_t i = 0; i < LAYOUTSNUM; ++i) {
        if (xkb_state_layout_index_is_active(STATE, i, XKB_STATE_LAYOUT_EFFECTIVE) == 1) {
            Log::logger->log(Log::DEBUG, "Updating keyboard {:x}'s translation state from an active index {}", rc<uintptr_t>(this), i);

            CVarList       keyboardLayouts(m_currentRules.layout, 0, ',');
            CVarList       keyboardModels(m_currentRules.model, 0, ',');
            CVarList       keyboardVariants(m_currentRules.variant, 0, ',');

            xkb_rule_names rules = {.rules = "", .model = "", .layout = "", .variant = "", .options = ""};

            std::string    layout, model, variant;
            layout  = keyboardLayouts[i % keyboardLayouts.size()];
            model   = keyboardModels[i % keyboardModels.size()];
            variant = keyboardVariants[i % keyboardVariants.size()];

            rules.layout  = layout.c_str();
            rules.model   = model.c_str();
            rules.variant = variant.c_str();

            auto KEYMAP = xkb_keymap_new_from_names2(PCONTEXT, &rules, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);

            if (!KEYMAP) {
                Log::logger->log(Log::ERR, "updateXKBTranslationState: keymap failed 1, fallback without model/variant");
                rules.model   = "";
                rules.variant = "";
                KEYMAP        = xkb_keymap_new_from_names2(PCONTEXT, &rules, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);
            }

            if (!KEYMAP) {
                Log::logger->log(Log::ERR, "updateXKBTranslationState: keymap failed 2, fallback to us");
                rules.layout = "us";
                KEYMAP       = xkb_keymap_new_from_names2(PCONTEXT, &rules, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);
            }

            m_xkbState       = xkb_state_new(KEYMAP);
            m_xkbStaticState = xkb_state_new(KEYMAP);
            m_xkbSymState    = xkb_state_new(KEYMAP);

            xkb_keymap_unref(KEYMAP);
            xkb_context_unref(PCONTEXT);

            return;
        }
    }

    Log::logger->log(Log::DEBUG, "Updating keyboard {:x}'s translation state from an unknown index", rc<uintptr_t>(this));

    xkb_rule_names rules = {
        .rules   = m_currentRules.rules.c_str(),
        .model   = m_currentRules.model.c_str(),
        .layout  = m_currentRules.layout.c_str(),
        .variant = m_currentRules.variant.c_str(),
        .options = m_currentRules.options.c_str(),
    };

    const auto NEWKEYMAP = xkb_keymap_new_from_names2(PCONTEXT, &rules, XKB_KEYMAP_FORMAT_TEXT_V2, XKB_KEYMAP_COMPILE_NO_FLAGS);

    m_xkbState       = xkb_state_new(NEWKEYMAP);
    m_xkbStaticState = xkb_state_new(NEWKEYMAP);
    m_xkbSymState    = xkb_state_new(NEWKEYMAP);

    xkb_keymap_unref(NEWKEYMAP);
    xkb_context_unref(PCONTEXT);
}

std::optional<xkb_layout_index_t> IKeyboard::getActiveLayoutIndex() {
    const auto KEYMAP     = m_xkbKeymap;
    const auto STATE      = m_xkbState;
    const auto LAYOUTSNUM = xkb_keymap_num_layouts(KEYMAP);

    for (xkb_layout_index_t i = 0; i < LAYOUTSNUM; ++i) {
        if (xkb_state_layout_index_is_active(STATE, i, XKB_STATE_LAYOUT_EFFECTIVE) == 1)
            return i;
    }

    return {};
}

std::string IKeyboard::getActiveLayout() {
    const auto KEYMAP     = m_xkbKeymap;
    const auto STATE      = m_xkbState;
    const auto LAYOUTSNUM = xkb_keymap_num_layouts(KEYMAP);

    for (uint32_t i = 0; i < LAYOUTSNUM; ++i) {
        if (xkb_state_layout_index_is_active(STATE, i, XKB_STATE_LAYOUT_EFFECTIVE) == 1) {
            const auto LAYOUTNAME = xkb_keymap_layout_get_name(KEYMAP, i);

            if (LAYOUTNAME)
                return std::string(LAYOUTNAME);
            return "error";
        }
    }

    return "none";
}

std::optional<uint32_t> IKeyboard::getLEDs() {
    if (m_xkbState == nullptr)
        return {};

    uint32_t leds = 0;
    for (uint32_t i = 0; i < std::min(sc<size_t>(LED_COUNT), m_ledIndexes.size()); ++i) {
        if (xkb_state_led_index_is_active(m_xkbState, m_ledIndexes[i]))
            leds |= (1 << i);
    }

    return leds;
}

void IKeyboard::updateLEDs() {
    std::optional<uint32_t> leds = getLEDs();

    if (!leds.has_value())
        return;

    updateLEDs(leds.value());
}

void IKeyboard::updateLEDs(uint32_t leds) {
    if (!m_xkbState)
        return;

    if (isVirtual() && g_pInputManager->shouldIgnoreVirtualKeyboard(m_self.lock()))
        return;

    if (!aq())
        return;

    aq()->updateLEDs(leds);
}

Input::ModifierMask IKeyboard::getModifiers() {
    uint32_t modMask     = m_modifiersState.depressed | m_modifiersState.latched;
    auto     getModState = [this, xkb = &modMask](const char* xkbModName) -> bool {
        auto IDX = xkb_keymap_mod_get_index(m_xkbKeymap, xkbModName);

        if (IDX == XKB_MOD_INVALID)
            return false;

        return (*xkb & (sc<uint32_t>(1) << IDX)) > 0;
    };

    Input::ModifierMask hl = Input::HL_MODIFIER_NONE;
    if (getModState(XKB_MOD_NAME_ALT))
        hl |= Input::HL_MODIFIER_ALT;
    if (getModState(XKB_MOD_NAME_CTRL))
        hl |= Input::HL_MODIFIER_CTRL;
    if (getModState(XKB_MOD_NAME_SHIFT))
        hl |= Input::HL_MODIFIER_SHIFT;
    if (getModState(XKB_MOD_NAME_CAPS))
        hl |= Input::HL_MODIFIER_CAPS;
    if (getModState(XKB_MOD_NAME_MOD2))
        hl |= Input::HL_MODIFIER_MOD2;
    if (getModState(XKB_MOD_NAME_MOD3))
        hl |= Input::HL_MODIFIER_MOD3;
    if (getModState(XKB_MOD_NAME_MOD4))
        hl |= Input::HL_MODIFIER_META;
    if (getModState(XKB_MOD_NAME_MOD5))
        hl |= Input::HL_MODIFIER_MOD5;

    return hl;
}

void IKeyboard::updateModifiers(uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {
    if (!m_xkbState)
        return;

    xkb_state_update_mask(m_xkbState, depressed, latched, locked, 0, 0, group);

    if (m_xkbSymState)
        xkb_state_update_mask(m_xkbSymState, 0, 0, 0, 0, 0, group);

    if (!updateModifiersState())
        return;

    m_keyboardEvents.modifiers.emit(SModifiersEvent{
        .depressed = m_modifiersState.depressed,
        .latched   = m_modifiersState.latched,
        .locked    = m_modifiersState.locked,
        .group     = m_modifiersState.group,
    });

    updateLEDs();
}

bool IKeyboard::updateModifiersState() {
    if (!m_xkbState)
        return false;

    auto depressed = xkb_state_serialize_mods(m_xkbState, XKB_STATE_MODS_DEPRESSED);
    auto latched   = xkb_state_serialize_mods(m_xkbState, XKB_STATE_MODS_LATCHED);
    auto locked    = xkb_state_serialize_mods(m_xkbState, XKB_STATE_MODS_LOCKED);
    auto group     = xkb_state_serialize_layout(m_xkbState, XKB_STATE_LAYOUT_EFFECTIVE);

    if (depressed == m_modifiersState.depressed && latched == m_modifiersState.latched && locked == m_modifiersState.locked && group == m_modifiersState.group)
        return false;

    m_modifiersState.depressed = depressed;
    m_modifiersState.latched   = latched;
    m_modifiersState.locked    = locked;
    m_modifiersState.group     = group;

    return true;
}

void IKeyboard::updateXkbStateWithKey(uint32_t xkbKey, bool pressed) {
    xkb_state_update_key(m_xkbState, xkbKey, pressed ? XKB_KEY_DOWN : XKB_KEY_UP);

    if (updateModifiersState()) {
        if (m_xkbSymState)
            xkb_state_update_mask(m_xkbSymState, 0, 0, 0, 0, 0, m_modifiersState.group);

        m_keyboardEvents.modifiers.emit(SModifiersEvent{
            .depressed = m_modifiersState.depressed,
            .latched   = m_modifiersState.latched,
            .locked    = m_modifiersState.locked,
            .group     = m_modifiersState.group,
        });
    }
}

bool IKeyboard::updatePressed(uint32_t key, bool pressed) {
    const auto contains = getPressed(key);

    if (contains && pressed)
        return false;
    if (!contains && !pressed)
        return false;

    if (contains)
        std::erase(m_pressed, key);
    else
        m_pressed.emplace_back(key);

    return true;
}

bool IKeyboard::getPressed(uint32_t key) {
    return std::ranges::contains(m_pressed, key);
}

bool IKeyboard::shareStates() {
    return m_shareStates;
}

void IKeyboard::setShareStatesAuto(bool shareStates) {
    if (m_shareStatesAuto)
        m_shareStates = shareStates;
}
