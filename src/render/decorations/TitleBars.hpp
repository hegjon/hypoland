#pragma once

#include "../../defines.hpp"
#include "../../helpers/Color.hpp"
#include "../../helpers/math/Math.hpp"
#include "../../helpers/signal/Signal.hpp"
#include "../../desktop/rule/windowRule/WindowRuleEffectContainer.hpp"
#include "../Texture.hpp"

#include <optional>
#include <string>
#include <vector>

// Titlebars for Omarchy's floating workspaces, built in instead of the omarchy-hyprland-titlebars plugin (a fork of
// hyprbars). They keep the plugin's interface, which Omarchy's config is written against: the plugin:hyprbars:*
// options, hl.plugin.hyprbars.add_button() and the hyprbars:* window rule effects. Off by default.
namespace TitleBars {
    using EffectID = Desktop::Rule::CWindowRuleEffectContainer::storageType;

    // a button added with hl.plugin.hyprbars.add_button()
    struct SButton {
        std::string               command;
        CHyprColor                background;
        std::optional<CHyprColor> foreground; // without one, white or black, whichever shows on the background
        float                     size = 10;
        std::string               icon;

        // the icon at the pixel size the last monitor drew it with, shared by every titlebar
        SP<Render::ITexture> iconTex;
        int                  iconTexSize = 0;

        CHyprColor           iconColor() const;
    };

    class CState {
      public:
        CState();

        std::vector<SButton> m_buttons;

        // the hyprbars:no_bar, hyprbars:bar_color and hyprbars:title_color window rule effects
        EffectID m_noBarEffect = 0, m_barColorEffect = 0, m_titleColorEffect = 0;

        // gives a window its titlebar decoration while titlebars are enabled, so windows cost nothing until then
        void attach(PHLWINDOW window);

      private:
        CHyprSignalListener m_windowOpen, m_windowRules, m_preReload, m_reloaded;
    };

    UP<CState>& state();

    // Every %WINDOW% replaced with the window's address (0x...), so a command that runs later still acts on the window
    // whose titlebar was clicked, whatever has the focus by then. No text of the window goes into the command.
    std::string windowCommand(std::string command, const std::string& address);

    // The buttons that fit on a bar of the given logical size, relative to the bar, in the order they were added:
    // from the right (or left) end after padding, buttonPadding apart. Buttons that do not fit are left out.
    std::vector<CBox> buttonBoxes(const std::vector<SButton>& buttons, const Vector2D& barSize, double padding, double buttonPadding, bool right);

    // how far a window's titlebar reaches above its surface, 0 without one: the border resize band runs above it
    int visibleHeight(PHLWINDOW window);
}
