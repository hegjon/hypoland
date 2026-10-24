// Ported from omarchy-hyprland-titlebars, a fork of hyprbars: see LICENSE.titlebars.

#include "CHyprTitleBarDecoration.hpp"
#include "TitleBars.hpp"
#include "../../animation/AnimationManager.hpp"
#include "../../config/ConfigValue.hpp"
#include "../../config/shared/animation/AnimationTree.hpp"
#include "../../config/shared/complex/ComplexDataTypes.hpp"
#include "../../config/shared/parserUtils/ParserUtils.hpp"
#include "../../config/supplementary/executor/Executor.hpp"
#include "../../desktop/state/FocusState.hpp"
#include "../../desktop/state/WindowState.hpp"
#include "../../desktop/view/window/Window.hpp"
#include "../../desktop/view/window/WindowMetadata.hpp"
#include "../../desktop/view/window/WindowPresentation.hpp"
#include "../../event/EventBus.hpp"
#include "../../helpers/AppNames.hpp"
#include "../../helpers/MiscFunctions.hpp"
#include "../../layout/LayoutManager.hpp"
#include "../../layout/supplementary/DragController.hpp"
#include "../../layout/target/Target.hpp"
#include "../../managers/fullscreen/FullscreenController.hpp"
#include "../../managers/input/InputManager.hpp"
#include "../pass/RectPassElement.hpp"
#include "../pass/TexPassElement.hpp"
#include "../Renderer.hpp"
#include "../Texture.hpp"

#include <linux/input-event-codes.h>

using namespace Render;

static CHyprColor configColor(Config::INTEGER color) {
    return CHyprColor(sc<uint64_t>(color));
}

CHyprTitleBarDecoration::CHyprTitleBarDecoration(PHLWINDOW pWindow) : IHyprWindowDecoration(pWindow), m_window(pWindow) {
    updateRules();
    setVisible(wantsVisible());
}

SDecorationPositioningInfo CHyprTitleBarDecoration::getPositioningInfo() {
    static auto                PHEIGHT     = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_height");
    static auto                PPRECEDENCE = CConfigValue<Config::BOOL>("plugin:hyprbars:bar_precedence_over_border");

    SDecorationPositioningInfo info;
    info.policy         = m_visible ? DECORATION_POSITION_STICKY : DECORATION_POSITION_ABSOLUTE;
    info.edges          = DECORATION_EDGE_TOP;
    info.priority       = *PPRECEDENCE ? 10005 : 5000; // inside the border (10000) or outside of it
    info.reserved       = true;
    info.desiredExtents = {{0, m_visible ? std::max<Config::INTEGER>(*PHEIGHT, 0) : 0}, {0, 0}};
    return info;
}

void CHyprTitleBarDecoration::onPositioningReply(const SDecorationPositioningReply& reply) {
    m_assignedBox = reply.assignedGeometry;
}

eDecorationType CHyprTitleBarDecoration::getDecorationType() {
    return DECORATION_TITLEBAR;
}

void CHyprTitleBarDecoration::initializeAnimations() {
    static auto PBARCOLOR = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_color");

    const auto  WINDOW = m_window.lock();
    if (!WINDOW)
        return;

    // the bar changes its color with the focus the way the border does
    Animation::mgr()->createAnimation(configColor(*PBARCOLOR), m_barColor, Config::animationTree()->getAnimationPropertyConfig("border"), WINDOW, AVARDAMAGE_NONE);
    m_barColor->setUpdateCallback([this](auto) { damageEntire(); });
}

bool CHyprTitleBarDecoration::wantsVisible() {
    static auto PENABLED = CConfigValue<Config::BOOL>("plugin:hyprbars:enabled");
    static auto PTAG     = CConfigValue<std::string>("plugin:hyprbars:workspace_tag");

    const auto  WINDOW = m_window.lock();
    if (!*PENABLED || !WINDOW || m_noBar || WINDOW->backend().traits().suggestsNoBorder || !WINDOW->m_ruleApplicator->decorate().valueOrDefault())
        return false;

    // with a tag only floating windows that carry it get a titlebar, and lose it as soon as they are tiled or untagged
    const auto TAG = *PTAG;
    return TAG.empty() || (WINDOW->isFloating() && WINDOW->m_ruleApplicator->m_tagKeeper.isTagged(TAG));
}

void CHyprTitleBarDecoration::setVisible(bool visible) {
    if (visible == m_visible)
        return;

    m_visible     = visible;
    m_dragPending = false;
    m_hoveredButton.reset();

    // the pointer is only followed while there is a bar, for dragging and for highlighting the buttons
    if (visible)
        m_mouseMove = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D coords, Event::SCallbackInfo&) { onMouseMove(coords); });
    else
        m_mouseMove.reset();

    // from the constructor the window does not hold the decoration yet, addDecoration() positions it
    const auto WINDOW = m_window.lock();
    if (!WINDOW || !WINDOW->mapped() || !WINDOW->presentation().containsDecoration(this))
        return;

    g_pDecorationPositioner->repositionDeco(this);
    if (WINDOW->layoutTarget())
        WINDOW->layoutTarget()->recalc();
    damageEntire();
}

void CHyprTitleBarDecoration::updateRules() {
    const auto WINDOW = m_window.lock();
    if (!WINDOW)
        return;

    const auto& PROPS  = WINDOW->m_ruleApplicator->m_otherProps.props;
    const auto& STATE  = TitleBars::state();
    const auto  effect = [&PROPS](TitleBars::EffectID id) -> std::optional<std::string> {
        const auto IT = PROPS.find(id);
        if (IT == PROPS.end() || !IT->second)
            return std::nullopt;
        return IT->second->effect;
    };
    const auto color = [](const std::optional<std::string>& value) -> std::optional<CHyprColor> {
        if (!value)
            return std::nullopt;
        const auto PARSED = Config::ParserUtils::parseColor(*value);
        return PARSED ? std::optional<CHyprColor>{configColor(*PARSED)} : std::nullopt;
    };

    const auto NOBAR      = effect(STATE->m_noBarEffect);
    const auto TITLECOLOR = color(effect(STATE->m_titleColorEffect));
    m_noBar               = NOBAR && truthy(*NOBAR);
    m_forcedBarColor      = color(effect(STATE->m_barColorEffect));
    m_titleDirty          = m_titleDirty || TITLECOLOR != m_forcedTitleColor;
    m_forcedTitleColor    = TITLECOLOR;
}

void CHyprTitleBarDecoration::updateWindow(PHLWINDOW) {
    updateRules();
    setVisible(wantsVisible());
    damageEntire();
}

void CHyprTitleBarDecoration::onConfigReloaded() {
    m_titleDirty = true;
    updateRules();
    setVisible(wantsVisible());

    // the height or the place next to the border may have changed
    g_pDecorationPositioner->repositionDeco(this);
    if (const auto WINDOW = m_window.lock(); WINDOW && WINDOW->layoutTarget())
        WINDOW->layoutTarget()->recalc();

    damageEntire();
}

int CHyprTitleBarDecoration::visibleHeight() {
    // the box is relative to the top of the window's surface, outside the border it starts that much higher
    return m_visible ? sc<int>(std::max(0.0, -m_assignedBox.y)) : 0;
}

CBox CHyprTitleBarDecoration::assignedBoxGlobal() {
    const auto WINDOW = m_window.lock();
    if (!WINDOW)
        return {};

    CBox box = m_assignedBox;
    box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_TOP, m_window));

    if (WINDOW->m_workspace && !(WINDOW->m_state & Desktop::View::WINDOW_STATE_PINNED))
        box.translate(WINDOW->m_workspace->m_renderOffset->value());

    return box.round();
}

void CHyprTitleBarDecoration::damageEntire() {
    const auto WINDOW = m_window.lock();
    if (!WINDOW || !m_visible)
        return;

    // with rounding, the corners filled under the bar too
    auto box = assignedBoxGlobal().translate(WINDOW->presentation().floatingOffset());
    box.h += WINDOW->presentation().rounding() + WINDOW->presentation().borderSize();
    g_pHyprRenderer->damageBox(box.expand(1));
}

std::optional<size_t> CHyprTitleBarDecoration::buttonAt(const Vector2D& barCoords) {
    static auto PPADDING       = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_padding");
    static auto PBUTTONPADDING = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_button_padding");
    static auto PALIGN         = CConfigValue<std::string>("plugin:hyprbars:bar_buttons_alignment");

    const bool  RIGHT = *PALIGN != "left";
    const auto  BOXES = TitleBars::buttonBoxes(TitleBars::state()->m_buttons, m_assignedBox.size(), *PPADDING, *PBUTTONPADDING, RIGHT);

    for (size_t i = 0; i < BOXES.size(); ++i) {
        // a button also takes the gap on its title side
        CBox hit = BOXES[i];
        if (RIGHT)
            hit.x -= *PBUTTONPADDING;
        hit.w += *PBUTTONPADDING;

        if (hit.containsPoint(barCoords))
            return i;
    }

    return std::nullopt;
}

void CHyprTitleBarDecoration::updateTitle(PHLWINDOW window, int maxWidth, float scale) {
    static auto PTEXTCOLOR = CConfigValue<Config::INTEGER>("plugin:hyprbars:col.text");
    static auto PTEXTSIZE  = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_text_size");
    static auto PFONT      = CConfigValue<std::string>("plugin:hyprbars:bar_text_font");
    static auto PWEIGHT    = CConfigValue<Config::IComplexConfigValue>("plugin:hyprbars:bar_text_weight");

    // The app's name is steadier than a window title, which for a web app is often just its domain or the page it
    // is on. Windows no launcher claims keep their title. Looked up again only when the class or title changes.
    const auto& CLASS = window->metadata().appID();
    const auto& TITLE = window->metadata().title();
    if (CLASS != m_windowClass || TITLE != m_windowTitle) {
        m_windowClass = CLASS;
        m_windowTitle = TITLE;

        auto name = AppNames::names()->nameFor(CLASS);
        if (name.empty())
            name = TITLE;
        if (name != m_title) {
            m_title      = std::move(name);
            m_titleDirty = true;
        }
    }

    const int SIZE = sc<int>(std::round(*PTEXTSIZE * scale));

    // While a window is resized the text only has to be drawn again when it no longer fits, or when it was cut short
    // and there is room for more, not on every frame.
    const bool CUTSHORT = m_titleTex && m_titleTex->m_size.x >= m_titleMaxWidth - 1;
    const bool REDRAW   = m_titleDirty || !m_titleTex || SIZE != m_titleSize || maxWidth < m_titleTex->m_size.x || (CUTSHORT && maxWidth > m_titleMaxWidth);
    if (!REDRAW)
        return;

    m_titleDirty    = false;
    m_titleSize     = SIZE;
    m_titleMaxWidth = maxWidth;

    if (m_title.empty() || maxWidth < 1) {
        m_titleTex = nullptr;
        return;
    }

    const auto WEIGHT = sc<Config::CFontWeightConfigValueData*>(PWEIGHT.ptr())->m_value;
    m_titleTex        = g_pHyprRenderer->renderText(m_title, m_forcedTitleColor.value_or(configColor(*PTEXTCOLOR)), SIZE, false, *PFONT, maxWidth, WEIGHT);
}

void CHyprTitleBarDecoration::draw(PHLMONITOR pMonitor, float const& a) {
    // floating, tags, rules and options all decide it, and a frame of the window is the moment to look
    setVisible(wantsVisible());

    if (!m_visible || !validMapped(m_window))
        return;

    static auto PBARCOLOR          = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_color");
    static auto PBARCOLORINACTIVE  = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_color_inactive");
    static auto PBLUR              = CConfigValue<Config::BOOL>("plugin:hyprbars:bar_blur");
    static auto PBLURGLOBAL        = CConfigValue<Config::BOOL>("decoration:blur:enabled");
    static auto PPRECEDENCE        = CConfigValue<Config::BOOL>("plugin:hyprbars:bar_precedence_over_border");
    static auto PTITLEENABLED      = CConfigValue<Config::BOOL>("plugin:hyprbars:bar_title_enabled");
    static auto PALIGN             = CConfigValue<std::string>("plugin:hyprbars:bar_text_align");
    static auto PBUTTONSALIGN      = CConfigValue<std::string>("plugin:hyprbars:bar_buttons_alignment");
    static auto PPADDING           = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_padding");
    static auto PBUTTONPADDING     = CConfigValue<Config::INTEGER>("plugin:hyprbars:bar_button_padding");
    static auto PINACTIVEBUTTON    = CConfigValue<Config::INTEGER>("plugin:hyprbars:inactive_button_color");
    static auto PBUTTONROUNDING    = CConfigValue<Config::INTEGER>("plugin:hyprbars:button_rounding");
    static auto PBUTTONBORDERSIZE  = CConfigValue<Config::INTEGER>("plugin:hyprbars:button_border_size");
    static auto PBUTTONBORDERCOLOR = CConfigValue<Config::INTEGER>("plugin:hyprbars:button_border_color");
    static auto PICONONHOVER       = CConfigValue<Config::BOOL>("plugin:hyprbars:icon_on_hover");

    const auto  WINDOW = m_window.lock();
    const auto  SCALE  = pMonitor->m_scale;
    const auto  BAR    = assignedBoxGlobal();
    CBox        bar    = BAR.copy().translate(-pMonitor->m_position + WINDOW->presentation().floatingOffset()).scale(SCALE).round();

    if (bar.w < 1 || bar.h < 1)
        return;

    const bool FOCUSED  = Desktop::focusState()->window() == WINDOW;
    const auto INACTIVE = *PBARCOLORINACTIVE;
    const auto GOAL     = m_forcedBarColor.value_or(configColor(!FOCUSED && INACTIVE != 0 ? INACTIVE : *PBARCOLOR));
    if (m_barColor && GOAL != m_barColor->goal())
        *m_barColor = GOAL;

    auto color = m_barColor ? m_barColor->value() : GOAL;
    color.a *= a;

    // The bar's top corners follow the window's rounding. The window's own top corners are rounded under the bar,
    // so the bar fills what they leave open: the bar is drawn under the window, which covers the rest.
    const int                   ROUNDING = sc<int>(std::round((WINDOW->presentation().rounding() + (*PPRECEDENCE ? 0 : WINDOW->presentation().borderSize())) * SCALE));
    const bool                  BLUR     = *PBLUR && *PBLURGLOBAL && color.a < 1.F;

    CRectPassElement::SRectData rect;
    rect.box   = bar;
    rect.color = color;
    rect.blur  = BLUR;
    if (ROUNDING > 0) {
        rect.round         = ROUNDING;
        rect.roundingPower = WINDOW->presentation().roundingPower();
        rect.box.h += ROUNDING;
        rect.clipBox = bar;
    }
    g_pHyprRenderer->addPassElement(makeUnique<CRectPassElement>(rect));

    if (ROUNDING > 0) {
        for (const double X : {bar.x, bar.x + bar.w - ROUNDING}) {
            CRectPassElement::SRectData corner;
            corner.box   = {X, bar.y + bar.h, sc<double>(ROUNDING), sc<double>(ROUNDING)};
            corner.color = color;
            corner.blur  = BLUR;
            g_pHyprRenderer->addPassElement(makeUnique<CRectPassElement>(corner));
        }
    }

    auto&      buttons      = TitleBars::state()->m_buttons;
    const bool BUTTONSRIGHT = *PBUTTONSALIGN != "left";

    if (*PTITLEENABLED) {
        // the title keeps clear of the buttons, on both sides when centered
        double buttonsWidth = *PBUTTONPADDING;
        for (const auto& b : buttons) {
            buttonsWidth += b.size + *PBUTTONPADDING;
        }

        const bool LEFT     = *PALIGN == "left";
        const int  MAXWIDTH = sc<int>(std::max(0.0, bar.w - (*PPADDING * 2 + buttonsWidth * (LEFT ? 1 : 2)) * SCALE));
        updateTitle(WINDOW, MAXWIDTH, SCALE);

        if (m_titleTex && m_titleTex->ok()) {
            const double                 X = LEFT ? std::round((*PPADDING + (BUTTONSRIGHT ? 0 : buttonsWidth)) * SCALE) :
                                                    std::round((bar.w - WINDOW->presentation().borderSize() * SCALE) / 2.0 - m_titleTex->m_size.x / 2.0);

            CTexPassElement::SRenderData data;
            data.tex = m_titleTex;
            data.box = CBox{bar.x + X, bar.y + std::round((bar.h - m_titleTex->m_size.y) / 2.0), m_titleTex->m_size.x, m_titleTex->m_size.y};
            data.a   = a;
            g_pHyprRenderer->addPassElement(makeUnique<CTexPassElement>(std::move(data)));
        }
    }

    const auto BOXES = TitleBars::buttonBoxes(buttons, BAR.size(), *PPADDING, *PBUTTONPADDING, BUTTONSRIGHT);
    for (size_t i = 0; i < BOXES.size(); ++i) {
        auto&      button = buttons[i];
        const CBox BOX    = BOXES[i].copy().scale(SCALE).translate(bar.pos()).round();

        auto       face = !FOCUSED && *PINACTIVEBUTTON != 0 ? configColor(*PINACTIVEBUTTON) : button.background;
        face.a *= a;

        // a negative rounding makes round buttons, as hyprbars draws them
        const int                   MAXROUND = sc<int>(std::round(BOX.w / 2.0));
        const int                   ROUND    = *PBUTTONROUNDING < 0 ? MAXROUND : std::clamp(sc<int>(std::round(*PBUTTONROUNDING * SCALE)), 0, MAXROUND);
        const int                   BORDER   = std::clamp(sc<int>(std::round(*PBUTTONBORDERSIZE * SCALE)), 0, MAXROUND);

        CRectPassElement::SRectData data;
        data.box   = BOX;
        data.round = ROUND;
        if (BORDER > 0) {
            data.color = configColor(*PBUTTONBORDERCOLOR);
            data.color.a *= a;
            g_pHyprRenderer->addPassElement(makeUnique<CRectPassElement>(data));
            data.box   = BOX.copy().expand(-BORDER);
            data.round = std::max(0, ROUND - BORDER);
        }
        data.color = face;
        g_pHyprRenderer->addPassElement(makeUnique<CRectPassElement>(data));

        // a hovered button lifts its face in its own icon color, which follows any theme
        if (m_hoveredButton == i) {
            data.box     = BOX;
            data.round   = ROUND;
            data.color   = button.iconColor();
            data.color.a = 0.18 * a;
            g_pHyprRenderer->addPassElement(makeUnique<CRectPassElement>(data));
        }

        if (button.icon.empty() || (*PICONONHOVER && !m_hoveredButton))
            continue;

        const int ICONSIZE = sc<int>(std::round(button.size * 0.62 * SCALE));
        if (!button.iconTex || button.iconTexSize != ICONSIZE) {
            button.iconTex     = g_pHyprRenderer->renderText(button.icon, button.iconColor(), ICONSIZE, false, "sans", BOX.w);
            button.iconTexSize = ICONSIZE;
        }

        if (!button.iconTex || !button.iconTex->ok())
            continue;

        CTexPassElement::SRenderData icon;
        icon.tex = button.iconTex;
        icon.box =
            CBox{BOX.x + (BOX.w - button.iconTex->m_size.x) / 2.0, BOX.y + (BOX.h - button.iconTex->m_size.y) / 2.0, button.iconTex->m_size.x, button.iconTex->m_size.y}.round();
        icon.a = a;
        g_pHyprRenderer->addPassElement(makeUnique<CTexPassElement>(std::move(icon)));
    }
}

bool CHyprTitleBarDecoration::onInputOnDeco(const eInputType type, const Vector2D& coords, std::any data) {
    static auto PDOUBLECLICK = CConfigValue<std::string>("plugin:hyprbars:on_double_click");

    if (type != INPUT_TYPE_BUTTON || !m_visible)
        return false;

    const auto& E      = std::any_cast<const IPointer::SButtonEvent&>(data);
    const auto  WINDOW = m_window.lock();
    if (E.button != BTN_LEFT || !WINDOW)
        return false;

    // The press never reaches the client, so neither does the release. A drag started from here ends with the release
    // wherever it happens (CKeybindManager::onMouseEvent).
    if (E.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        m_dragPending = false;
        return true;
    }

    if (Desktop::focusState()->window() != WINDOW)
        Desktop::focusState()->fullWindowFocus(WINDOW, Desktop::FOCUS_REASON_CLICK);

    if (WINDOW->isFloating())
        Desktop::windowState()->raise(WINDOW);

    // commands name the window by its address, as hyprctl and hl.get_windows() do
    const auto ADDRESS = std::format("0x{:x}", rc<uintptr_t>(WINDOW.get()));

    if (const auto BUTTON = buttonAt(coords - assignedBoxGlobal().pos()); BUTTON) {
        Config::Supplementary::executor()->spawn(TitleBars::windowCommand(TitleBars::state()->m_buttons[*BUTTON].command, ADDRESS));
        return true;
    }

    const auto NOW         = Time::steadyNow();
    const auto DOUBLECLICK = *PDOUBLECLICK;
    if (!DOUBLECLICK.empty() && NOW - m_lastPress < std::chrono::milliseconds(400)) {
        m_lastPress   = {};
        m_dragPending = false;
        Config::Supplementary::executor()->spawn(TitleBars::windowCommand(DOUBLECLICK, ADDRESS));
        return true;
    }

    // the drag starts with the first motion, so a click or double click leaves the window where it is
    m_lastPress   = NOW;
    m_pressCoords = coords;
    m_dragPending = true;
    return true;
}

void CHyprTitleBarDecoration::onMouseMove(const Vector2D& coords) {
    if (!validMapped(m_window))
        return;

    if (m_dragPending)
        startDrag();

    const auto            BAR = assignedBoxGlobal();
    std::optional<size_t> hovered;
    if (BAR.containsPoint(coords))
        hovered = buttonAt(coords - BAR.pos());

    if (hovered == m_hoveredButton)
        return;

    m_hoveredButton = hovered;
    damageEntire();
}

void CHyprTitleBarDecoration::startDrag() {
    m_dragPending = false;

    const auto WINDOW = m_window.lock();
    if (!WINDOW || !WINDOW->layoutTarget() || g_layoutManager->dragController()->target())
        return;

    // The drag starts with the first motion after the press, and follows the pointer from where it is then. The window
    // is brought to where the press would have dragged it, so it stays under the pointer.
    const auto CURSOR = g_pInputManager->getMouseCoordsInternal();
    const auto TARGET = WINDOW->layoutTarget();

    if (Fullscreen::controller()->isFullscreen(WINDOW, Fullscreen::FSMODE_MAXIMIZED)) {
        // a maximized window comes back to its floating size, held at the spot of its titlebar that was pressed
        const auto   BAR    = assignedBoxGlobal();
        const double ANCHOR = std::clamp((m_pressCoords.x - BAR.x) / std::max(1.0, BAR.w), 0.0, 1.0);
        const double OFFSET = std::clamp(m_pressCoords.y - BAR.y, 0.0, BAR.h);
        const int    ABOVE  = visibleHeight();

        Fullscreen::controller()->setFullscreenMode(WINDOW, Fullscreen::FSMODE_NONE);

        auto box = TARGET->position();
        box.x    = CURSOR.x - box.w * ANCHOR;
        box.y    = CURSOR.y - OFFSET + ABOVE;
        g_layoutManager->setTargetGeom(box, TARGET);
        TARGET->warpPositionSize();
    } else if (WINDOW->isFloating())
        g_layoutManager->moveTarget(CURSOR - m_pressCoords, TARGET);

    g_layoutManager->beginDragTarget(TARGET, MBIND_MOVE);
}

eDecorationLayer CHyprTitleBarDecoration::getDecorationLayer() {
    return DECORATION_LAYER_UNDER;
}

uint64_t CHyprTitleBarDecoration::getDecorationFlags() {
    static auto PPARTOFWINDOW = CConfigValue<Config::BOOL>("plugin:hyprbars:bar_part_of_window");
    return DECORATION_ALLOWS_MOUSE_INPUT | (*PPARTOFWINDOW ? DECORATION_PART_OF_MAIN_WINDOW : 0);
}

std::string CHyprTitleBarDecoration::getDisplayName() {
    return "TitleBar";
}
