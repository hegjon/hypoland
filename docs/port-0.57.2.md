# Hyprland 0.57.1 and 0.57.2: what Hypoland takes

Every upstream commit between v0.57.0 and v0.57.2 (`git log --no-merges v0.57.0..v0.57.2`), in order, and what was done
with it on 2026-11-10 on the branch `port/0.57.2` (from master 29b9f86a9), replayed on 2026-11-15 on master bdc0ebdad as
`port/0.57.2-r2`. The point releases are fixes on top of
0.57.0, so most could be taken. "Picked" is a cherry-pick (`-x`), with the conflicts settled as said; "by hand" is the
fix written again on Hypoland's code; "tests only" takes upstream's tests for a bug Hypoland does not have; "later"
waits for an upstream change Hypoland has not taken; "ignore" is not taken. Conflicts were mostly in hyprtester tests
that use the test plugin (removed in Hypoland) or kitty (Hypoland's tests open foot), in `LOG` / `LOGM` (Hypoland's
protocols still log with `LOGM`), and in code upstream reworked after Hypoland's base. Hypoland's own commit for each
is on the branch with upstream's subject and author.

| commit | decision | subject |
|---|---|---|
| 1977743e3 | already in master: acf42ff16 rounds the group bar's box in the monitor's pixels the same way, and 1d594db8a damages every pixel a box touches (`Math::coveredPixels()`) | decoration/groupbar: round boxes in device space to match damage (#16687) |
| de4a49c50 | picked | config/lua: fix validator for custom accel profiles (#16730) |
| aec6a54c0 | already in master: e5a1c2d8e draws a small surface at its logical size (found on samsung-i5 with vkmark at scale 1.5) and centres the whole surface tree; the pick of 2026-11-10 was dropped in the replay | renderer: draw small surfaces at their logical size (#16711) |
| 6d698d958 | picked, the include it adds to hyprtester's xdg-interactive client left out (Hypoland has no such client) | window: preserve fullscreen on client maximize requests |
| 82109f958 | picked: only its unit tests are new, Hypoland's default of `quirks:skip_non_kms_dmabuf_formats` has been false all along (Gen4 primary planes have no alpha formats), and the tests expect false | config: restore opt-in KMS dmabuf filtering |
| 7a648e3ed | picked, `LOGM` kept: feedback sent after a format table reset used the indices of the old table; a monitor without a tranche now gets the default feedback. The scanout tranche the direct scanout auto offers goes through the same `updateScanoutTranche()`, unchanged otherwise | protocols/dmabuf: use replacement table for feedback updates |
| 04d93b8f3 | picked, `LOGM` kept; no default changed | protocols/dmabuf: refresh format feedback after config updates |
| 079918228 | picked | config/values: adjust limits for tablet values (#16782) |
| 044293717 | tests only: the underflow is in upstream's workspace resolver (`src/state/workspace/Resolver.cpp`) of the workspace refactor e9e2f64cc; Hypoland's walk in `getWorkspaceIDNameFromString()` searches forward from the first valid workspace and already stays on the monitor. Both tests pass, with foot, the "workspace ID N (N)" text and an output of their own (HEADLESS-6: an output that comes back gets its last workspace, which broke workspacesCombined after them on HEADLESS-3) | state/workspace: fix underflow in r parsing resulting in a bad return (#16786) |
| 518be87ef | picked, `LOGM` kept; its unit test added to Hypoland's smaller `tests/protocols/Output.cpp` with the parts of the fixture it needs | protocols/session-lock: fix removed output causing a protocol error (#16784) |
| 134e971ee | picked, its hyprtester test left out (test plugin) | keybinds: do not shadow mouse event inputs (#16788) |
| 253924bb3 | ignore: needs the output state's max bpc of aquamarine 0.15 (the embedded aquamarine has no `setMaxBpc()`), and Hypoland ignores `bitdepth = 10` (GLES 2 cannot render into 10-bit buffers), so it would only ever ask for 8 | monitor: set max_bpc based on configured bitdepth (#16708) |
| 31af0bbba | picked, its hyprtester test left out (test plugin) | keybinds: fix _consuming exceptions for chord resolving (#16806) |
| d530c26f5 | ignore: upstream's VERSION; `VERSION_HYPRLAND` stays 0.57.0 until the user decides | VERSION: bump to 0.57.1 |
| acc1aa0bf | ignore: Nix, removed in Hypoland | [gha] Nix: update inputs |
| 5c076e645 | picked, only the early return at shutdown (the erase of expired targets next to it came with 04615f9af, not taken) | algo/scroll: remove redundant cleanup of FS lists when compositor shutdown requested (#16792) |
| a66bc70fb | picked, its unit test taken, the hyprtester change left out (test plugin) | keybinds: fix modifier resolution when remapped (#16820) |
| e65d6d131 | picked, `LOGM` kept and `NON_MOVABLE` written out (Hypoland has no `macros/Class.hpp`); upstream's xdg-activation client test is not in Hypoland. A token asked for without a valid serial (foot's urgency bell) now makes the window urgent instead of being refused | protocols/activation: send urgent-only tokens if serial is missing (#16827) |
| cba094604 | picked | core: enable prctl(2) only on Linux (#16839) |
| cce85dc11 | ignore (Hypoland's guard), the user decides: upstream drops realtime scheduling because a long kernel call can overrun rtkit's hard limit and get SIGKILL; Hypoland keeps realtime with its guard thread (`guardRealtime()`, AGENTS.md "Realtime and its guard"), which takes it away before that, and measured realtime worth keeping | init: stop acquiring realtime scheduling |
| b9e785380 | picked; the two new log lines say Hypoland like start-hypoland's others, and its ctest expects them so and does not pass the removed `--no-nixgl` (4 of 4 pass) | start: handle and report signal-terminated children |
| a29e91e9f | picked; its hyprtester test opens foot with a locked title | config/lua: fix accessing an expired window ref from a lua object (#16853) |
| d8962b2db | picked; the frame is counted after Hypoland's last early return (upstream's commit coordinator check is not in Hypoland) | overlay: fix double counting when present early exited. (#16834) |
| b280c55a2 | picked: a background or bottom layer that maps while a window is fullscreen no longer stays invisible after it | core/layers: allow bottom layers and background layers under fs (#16740) |
| ef9abc0b9 | by hand: Hypoland's `beginBackdropScope()` has no render context; the clean backdrop for live blur is copied over the scope's damage grown by the blur's reach. Only with blur on (off by default) | render: fix invalidation artifacts with two floating overlapped windows (#16888) |
| d7f16472a | ignore: `cm_helpers.glsl` went with colour management | helpers/cm: fix small typo in calculating brightness saturation (#16897) |
| f1c344c47 | picked | core/fullscreen: fix client_requested_fs_uses_layout_handler being handled incorrectly for some programs (#16870) |
| 24fda1aa0 | picked, `m_space` for upstream's `space()`; its test opens foot | window: allow unpinning window onto special workspace (#16854) |
| d9f7598b1 | picked; `decoration:shadow:scale` is a no-op since shadows were removed, its lower limit follows upstream so the same configs load | config/values: adjust limits again (#16898) |
| 6cc4567fe | by hand: Hypoland's `syncFullscreenTargets()` is the one before upstream's rework (04615f9af), the fix applied to it (with a check that the target still has a column); its test opens foot | scrolling/fullscreen: fix only internal un-FS not restoring prev col width (#16896) |
| f0d381868 | later: needs `CInputManager::refocusPointer()`, a pointer-only mouse move that came with the pointer constraint refactor 5e04ae1f9, not taken. When it comes, the pointer-only move has to keep a hidden cursor hidden as `simulateMouseMovement()` does (`m_simulatedMovement`, the menu close fix of 2026-10-27) | desktop/layerSurface: use refocusPointer instead of simulate on map (#16902) |
| 8a0659172 | picked | seat: fix grab check (#16900) |
| f6e27b1c7 | picked | layout/floating: preserve parent-relative window placement |
| 680866d61 | picked | protocols/subcompositor: fix nested ancestor traversal |
| 86688ae74 | picked, without its image description parts (`getPreferredImageDescription()` went with colour management, and its two tests) | protocols/subcompositor: handle expired ancestry during teardown |
| c44c4be61 | ignore: Nix, removed in Hypoland | flake: update inputs |
| 11cbc6c57 | ignore: upstream's VERSION | VERSION: bump to 0.57.2 |

- 25 picked
- 7 ignore
- 2 by hand
- 1 tests only
- 1 later
- 1 already in master
