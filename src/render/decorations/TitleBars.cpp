// Ported from omarchy-hyprland-titlebars, a fork of hyprbars: see LICENSE.titlebars.

#include "TitleBars.hpp"
#include "CHyprTitleBarDecoration.hpp"
#include "../../config/ConfigValue.hpp"
#include "../../desktop/state/WindowState.hpp"
#include "../../desktop/view/window/Window.hpp"
#include "../../desktop/view/window/WindowPresentation.hpp"
#include "../../event/EventBus.hpp"
#include "DecorationPositioner.hpp"

#include <cmath>

using namespace TitleBars;

CHyprColor SButton::iconColor() const {
    return foreground.value_or(background.r + background.g + background.b < 1 ? CHyprColor(0xFFFFFFFF) : CHyprColor(0xFF000000));
}

CState::CState() {
    m_noBarEffect      = Desktop::Rule::windowEffects()->registerEffect("hyprbars:no_bar");
    m_barColorEffect   = Desktop::Rule::windowEffects()->registerEffect("hyprbars:bar_color");
    m_titleColorEffect = Desktop::Rule::windowEffects()->registerEffect("hyprbars:title_color");

    m_windowOpen  = Event::bus()->m_events.window.open.listen([this](PHLWINDOW w) { attach(w); });
    m_windowRules = Event::bus()->m_events.window.updateRules.listen([this](PHLWINDOW w) { attach(w); });

    // the config adds its buttons again on every load
    m_preReload = Event::bus()->m_events.config.preReload.listen([this] { m_buttons.clear(); });
    m_reloaded  = Event::bus()->m_events.config.reloaded.listen([this] {
        // the first load comes before there are windows, or anything to place a decoration with
        if (!g_pDecorationPositioner)
            return;

        for (const auto& w : Desktop::windowState()->windows()) {
            if (!w->mapped())
                continue;

            attach(w);
            if (const auto DECO = w->presentation().decoration(DECORATION_TITLEBAR); DECO)
                sc<CHyprTitleBarDecoration*>(DECO.get())->onConfigReloaded();
        }
    });
}

void CState::attach(PHLWINDOW window) {
    static auto PENABLED = CConfigValue<Config::BOOL>("plugin:hyprbars:enabled");

    if (!*PENABLED || !window || !g_pDecorationPositioner || window->presentation().decoration(DECORATION_TITLEBAR))
        return;

    window->presentation().addDecoration(makeShared<CHyprTitleBarDecoration>(window));
}

UP<CState>& TitleBars::state() {
    static UP<CState> p = makeUnique<CState>();
    return p;
}

std::string TitleBars::windowCommand(std::string command, const std::string& address) {
    constexpr std::string_view TOKEN  = "%WINDOW%";
    size_t                     offset = 0;
    while ((offset = command.find(TOKEN, offset)) != std::string::npos) {
        command.replace(offset, TOKEN.size(), address);
        offset += address.size();
    }
    return command;
}

std::vector<CBox> TitleBars::buttonBoxes(const std::vector<SButton>& buttons, const Vector2D& barSize, double padding, double buttonPadding, bool right) {
    std::vector<CBox> boxes;
    double            space  = barSize.x - padding * 2;
    double            offset = padding;

    for (const auto& b : buttons) {
        if (space < b.size + buttonPadding)
            break;

        space -= b.size + buttonPadding;
        boxes.emplace_back(std::floor(right ? barSize.x - offset - b.size : offset), std::floor((barSize.y - b.size) / 2.0), b.size, b.size);
        offset += b.size + buttonPadding;
    }

    return boxes;
}

int TitleBars::visibleHeight(PHLWINDOW window) {
    if (!window)
        return 0;

    const auto DECO = window->presentation().decoration(DECORATION_TITLEBAR);
    return DECO ? sc<CHyprTitleBarDecoration*>(DECO.get())->visibleHeight() : 0;
}
