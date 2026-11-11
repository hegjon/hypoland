-- For the stock Hyprland 0.57.0 blocks of the baseline (all machines): advertise every format the renderer can sample,
-- as Hypoland does by default, not only those the primary plane can scan out. With the upstream default
-- (quirks:skip_non_kms_dmabuf_formats = true) a stock 0.57.0 session under Omarchy r7438 on the T550 (Broadwell) had no
-- wallpaper, half a bar, and EGL clients that ask for alpha found no config (weston-simple-egl: init_egl assertion), so
-- most workloads measured nothing; 0.56.2 did not have that. Required from envs.lua by abnight.sh for those blocks only.
hl.config({ quirks = { skip_non_kms_dmabuf_formats = false } })
