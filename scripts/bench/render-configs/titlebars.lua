-- the built-in titlebars as Omarchy sets them up for floating workspaces (default/hypr/workspace-modes.lua), on every
-- floating window here: the checks' dialog floats
hl.plugin.load("/usr/lib/omarchy-hyprland-titlebars/titlebars.so")
hl.config({ plugin = { hyprbars = {
    enabled = true, bar_height = 30, bar_color = 0xff2e3440, col = { text = 0xffd8dee9 }, bar_text_font = "monospace",
    bar_text_size = 12, bar_text_align = "left", bar_part_of_window = true, bar_precedence_over_border = true,
    bar_padding = 10, bar_button_padding = 8, button_rounding = 0,
} } })
hl.plugin.hyprbars.add_button({ bg_color = 0xff2e3440, fg_color = 0xffd8dee9, size = 20, icon = "×", action = "true" })
hl.plugin.hyprbars.add_button({ bg_color = 0xff2e3440, fg_color = 0xffd8dee9, size = 20, icon = "□", action = "true" })
