-- Omarchy's own look (default/hypr/looknfeel.lua of 2026-11): gaps and borders with the gradient active border, square
-- corners, the group bar (22 high, gradients, an indicator, text) and Omarchy's animations (easeOutQuint, popin 95%).
-- On its own, not on top of base.lua
local active_border_color = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
local inactive_border_color = "rgba(595959aa)"

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 10,
        border_size = 2,
        col = { active_border = active_border_color, inactive_border = inactive_border_color },
    },
    decoration = { rounding = 0 },
    group = {
        col = { border_active = active_border_color, border_inactive = inactive_border_color },
        groupbar = {
            font_size = 12,
            font_family = "monospace",
            font_weight_active = "ultraheavy",
            font_weight_inactive = "normal",
            indicator_height = 1,
            indicator_gap = 5,
            height = 22,
            gaps_in = 5,
            gaps_out = 0,
            text_color = "rgb(ffffff)",
            text_color_inactive = "rgba(ffffff90)",
            col = { active = "rgba(00000040)", inactive = "rgba(00000020)" },
            gradients = true,
            gradient_rounding = 0,
            gradient_round_only_edges = false,
        },
    },
    animations = { enabled = true },
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.animation({ leaf = "global",        enabled = true, speed = 2.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "border",        enabled = true, speed = 1.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 2.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 95%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.6, bezier = "easeOutQuint", style = "popin 95%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.8, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.2, bezier = "easeOutQuint" })
hl.animation({ leaf = "fade",          enabled = true, speed = 2,   bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeSwitch",    enabled = false })
hl.animation({ leaf = "layers",        enabled = true, speed = 2.5, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.6, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.8, bezier = "easeOutQuint" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.2, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces",    enabled = false })
