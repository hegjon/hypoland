# Hyprland 0.57.0: what Hypoland takes

Every upstream commit between Hypoland's base (d8504461f, upstream main at 0.56.0+141) and v0.57.0, in order, and what
was done with it on 2026-10-30, merged into master that evening. On master, the first 28 picks of 2026-10-28 (branch
`port/0.57.0`) were replayed, 18 more picked with their test conflicts settled, the rest of 0.57.0's config surface written on
Hypoland's own code, and one fixup (`IKeyboard::isVirtual()` is const). "Later" marks commits whose conflicts sit in
code the workspace refactor (e9e2f64cc) rewrote; they wait for that port. "Ignore" marks CI, docs, reverts, and code
Hypoland removed (the scene composition renderer, colour management, FP16 buffers, the test plugin, Nix). The dry-run
cherry-pick that classified the conflicts ran against master f967f8cff, so a commit marked clean may still conflict once
others are in, and the other way round.

| commit | decision | subject |
|---|---|---|
| 0bd11c7a0 | later or ignore: renderer/output conflicts | renderer: fix blur region transformations (#15970) |
| 9631188c1 | picked | desktop/windowRule: add no_glow window rule (#15863) |
| e90da09e9 | later or ignore: renderer/output conflicts | renderer: clear blur FBs on disabled blur (#16015) |
| 3b1aa6be7 | later: conflicts in  | algo/master: fix some master layout window-drag bugs (#15956) |
| 8d9868c93 | already in master | protocols/dataDeviceWlr: don't send primary selection to version 1 (#16034) |
| 41718b097 | ignore: only touches code Hypoland removed | [gha] Nix: update inputs |
| 62b40e1d0 | later: conflicts in BellSound.cpp | bell: play threaded (#16033) |
| 60695e18c | ignore: CI Hypoland removed | ci/vouch: Allow vouched people to open issues (#15796) |
| c91fa5ab4 | already in master | fullscreen: fix missing early return (#16063) |
| e43eaaac6 | already in master | config/lua: fix misspelling of `damping` as `dampening` for spring animations (#15993) |
| 503f9fc7f | already in master | cursor: update cursor image on theme change (#16036) |
| ebc37ccc1 | later: conflicts in CMakeLists.txt flake.lock Math.cpp Math.hpp | input/pointer: use aq output hints for absolute warps (#15927) |
| ee058bc47 | ignore: needs aquamarine 0.15 (render:async_commit accepted and ignored) | output: add async commit scheduling for page flips (#15991) |
| 86c24e2e0 | ignore: only touches code Hypoland removed | hyprpm: make hyprwayland-scanner runtime dep explicit (#16047) |
| 3b2dadd98 | picked (the port branch of 2026-10-28) | gestures: fix clangd error -> equation precedence. (#16074) |
| 4a4a5279a | picked (the port branch of 2026-10-28) | config/events: add config.unload event (#16005) |
| 7f4b6169f | ignore: upstream's AGENTS.md | Agents.md: Update with issue, discussion, and PR guidelines (#16023) |
| 6813bbcae | already in master | groups: fixes for groupbar:disable_when_only (#16037) |
| d7a43351a | later: test build files conflict | protocols/xdg-shell: don't maximize on toplevel map (#16013) |
| eb97c46a5 | picked, the test build files resolved | config/lua: add minimize event (#16071) |
| c1239d02e | later: conflicts in vouch_issue_message.md | Core/Guidelines: update CLAUDE.md for claude and AI policy (#16099) |
| 59177602f | later: conflicts in main.cpp Compositor.cpp Canberra.cpp ConfigManager.cpp LuaEventHandler.cpp IKeyb | log: update logging macro to include callsite (#16111) |
| 304bbec7d | already in master | protocols: clear data control primary selection (#16117) |
| e329b6171 | picked | groups: fix comment (#16100) |
| fec44ae32 | later: conflicts only in tests or build files | layout/scrolling: make mouse click viewport move consistent across all `follow_mouse` options (#15975) |
| cb537a387 | picked | splashes: remove jacekpoz splash |
| d4ed4a9ad | later: conflicts only in tests or build files | input/gesture: allow for negative scale on scroll move gesture (#16072) |
| 34ce98269 | later or ignore: renderer/output conflicts | renderer/gl: fix blur noise intensity in HDR (#16120) |
| c0e2be756 | later: conflicts only in tests or build files | seat: implement input redirecting (#16141) |
| 01be2db87 | ignore: only touches code Hypoland removed | [gha] Nix: update inputs |
| 5584938a9 | later: conflicts in main.cpp InputManager.cpp Ripple.cpp Water.cpp | pointer: add pointer transforms (#16143) |
| ee0409623 | later: conflicts only in tests or build files | internal: minor fixes from overview mr (#16145) |
| 2eb5180c6 | picked (the port branch of 2026-10-28) | ipc/s1: expose monitor details via s1 (#16152) |
| ab136393c | picked, the plugin-system part left out | config/lua: add `reload_config()` api (#16108) |
| 214bb0e5b | picked (the port branch of 2026-10-28) | tests: Test that windows lose and regain focus when switching workspaces (#16153) |
| 34eb03bd8 | picked (the port branch of 2026-10-28) | config/lua: expose monitor mode, other hardware details (#16149) |
| 7ebf13abb | later: test build files conflict | screencopy/toplevel: fix top level capture (#16132) |
| e9e2f64cc | later: the workspace refactor (163 files), the base of most later conflicts | workspace: refactor workspace handling (#16140) |
| 04615f9af | later: conflicts in ScrollingFullscreenHandler.cpp | core/fullscreen: improve `syncFullscreenTargets()`, account for an edge case, misc. improvements (#16069) |
| 599ff9042 | later: conflicts only in tests or build files | desktop/windowRule: add active_border and inactive_border rules (#15581) |
| f05d73f35 | already in master | input/scroll: set scroll_factor from 2.00 --> 100.00 (#16135) |
| 7aa195cf5 | ignore: only touches code Hypoland removed | github: update template with AI disclosure header (#16199) |
| 584baca32 | ignore: reverted by 747b2f83a | input: allow pointer constraints to work on subsurface (#15435) |
| 0b7e96f8b | later: conflicts only in tests or build files | hid: make isVirtual() const (#16209) |
| 6e95f93f1 | later or ignore: renderer/output conflicts | workspace: fix anim in/out on special (#16227) |
| 3a37b75f6 | later: conflicts in  | layout/floating: fix "move" rule not using the size provided by the "size" rule (#16150) |
| 747b2f83a | ignore: the revert | input: revert "allow pointer constraints to work on subsurface (#15435)" |
| c31b90c5f | already in master | xwayland: handle _NET_WM_STATE_DEMANDS_ATTENTION (#16205) |
| be8d7c676 | already in master | config/lua: fix potential crash in error prints (#16246) |
| 1b85c7aa1 | later: conflicts in hyprland.lua | config: link to the new wiki pages (#16241) |
| c26dbf933 | later: conflicts in main.cpp | main: check XDG_RUNTIME_DIR later (#16256) |
| a94bc95ff | later: conflicts in workspaces.cpp FocusState.cpp Window.cpp Monitor.cpp WorkspacePlacementControlle | workspace: create named workspaces for bare named lookups (#16234) |
| 92b82c0c1 | later: conflicts in ScrollingFullscreenHandler.cpp | fullscreen: fix floating window focus loss on workspace change when covering FS window present (#16168) |
| d50ca8950 | later: conflicts in Window.cpp Window.hpp Commands.cpp AbstractWorkspace.cpp AbstractWorkspace.hpp Q | ipc: clean up workspace data (#16269) |
| 8bc742ad2 | later: conflicts in Monitor.cpp HLWorkspace.cpp | ipc: fix inconsistent workspace events (#16292) |
| 5fbb2a7ac | ignore: only touches code Hypoland removed | [gha] Nix: update inputs |
| 9a4a0ad22 | ignore: discussions template | Discussions: Add TriggerHappy - Moderation Tool for Discussions (#16157) |
| 83cf6a6ed | ignore: only touches code Hypoland removed | ci/discussions: regex tweak (#16307) |
| 16a228056 | ignore: reverted by 9f0b86409 | screencopy: schedule new frames on damage (#16333) |
| 9f0b86409 | ignore: the revert | screencopy: revert "schedule new frames on damage (#16333)" |
| fc2367b4f | later: conflicts in InputCapture.cpp | input-capture: implement the session destroy request (#16204) |
| 23118f9f7 | later: conflicts in WorkspaceRuleManager.cpp Resolver.cpp WorkspaceFilter.cpp Query.cpp WorkspaceRul | workspace: reject workspaces named as IDs (#16319) |
| e368c13c2 | already in master | permissions: listen to client destroy instead of display (#16353) |
| 4fee76945 | later: conflicts in AGENTS.md README.md ISSUE_GUIDELINES.md default.nix overlays.nix Compositor.cpp | ci/docs: update links to point to new wiki (#16375) |
| 7aa70b6c5 | later: conflicts in hyprctl.1 | [gha] build man pages |
| c6f117211 | picked (the port branch of 2026-10-28) | socket1: fix missing enabled invert for json in get monitor (#16363) |
| b36699fac | later: conflicts in Window.cpp | tokens: fix tokens not updating when using autostart (#16314) |
| 9a1ea2927 | in master through the port branch | screencopy: fix recording blocking DS indefinitely (#16361) |
| 4bb6844b0 | later: conflicts in StringUtils.hpp StringUtils.cpp | render: detect software rendering from the GL renderer (#16343) |
| 7d3a817ff | picked (the port branch of 2026-10-28) | input/tablet: add `input:tablet:enabled` (#16380) |
| f33e6a01e | picked (the port branch of 2026-10-28) | surface: allow pointer constraints to work on subsurface (#16311) |
| a6bca359b | later: conflicts in main.cpp Renderer.cpp | render: add scene composition (#16340) |
| 6b87cbf25 | ignore: FP16 work buffers are removed | renderer: fix snapshots using FP8 buffers when workbuffer is FP16 (#16321) |
| a2177f1fb | already in master | protocols/bell: fix crash on null surface provided (#16428) |
| ce2167a23 | picked, its hyprtester test left out (needs the test plugin) | config/lua: add hl.get_devices() (#16429) |
| 156276e51 | later: test build files and XDGActivation | protocols/activation: reject invalid serials (#16427) |
| b2f1b42ca | later: conflicts only in tests or build files | keybinds: preserve drag threshold while a target is active |
| bf0c08540 | later or ignore: test plugin | renderer: preserve parent fade when rendering popups |
| e60298a7e | later: conflicts only in tests or build files | renderer: respect pass redirection for window popups |
| 35567d25c | later: conflicts only in tests or build files | renderer: deduplicate monitor background rendering |
| 11c088674 | later or ignore: renderer/output conflicts | render/opengl: remove unused render declarations |
| 216f958a0 | ignore: only touches code Hypoland removed | hyprtester: wait for popup render fixtures to settle |
| e82631720 | ignore: only touches code Hypoland removed | hyprtester: release the drag button on test failures |
| 90272770c | later: conflicts in Makefile main.cpp UnifiedWorkspaceSwipeGesture.cpp | input: centralize workspace swipe cleanup |
| aa23aeb8d | later: conflicts in WorkspaceGestures.cpp workspace_swipe.cpp UnifiedWorkspaceSwipeGesture.cpp Unifi | input: bind workspace swipes to their origin and input session |
| abb4afc74 | later: conflicts in Makefile main.cpp SpecialWorkspaceGesture.cpp | input: bound special workspace gesture lifetime |
| 1a9b220f1 | later or ignore: renderer/output conflicts | renderer: expire idle workbuffers and budget sized allocations in bytes |
| 66408d997 | later: conflicts in LinuxDMABUF.cpp MesaDRM.cpp DMABUF.cpp | protocols/dmabuf: own plane fds throughout buffer creation |
| 9c85920a0 | later: conflicts in LinuxDMABUF.cpp | protocols/dmabuf: remove SP<> allocation for attrs |
| 6ef51fff5 | later: conflicts in VirtualPointer.cpp | protocols/virtualPointer: fix axis check for protocol erroring (#16438) |
| 3d4e2b3bc | later: conflicts in LuaBindingsToplevel.cpp StringUtils.hpp StringUtils.cpp | config/lua: reject duplicated keys in a bind string in hl.bind |
| fd1344bcc | picked (the port branch of 2026-10-28) | config/lua: reject dispatcher factories in bind and dispatch |
| 59ab177fb | later: conflicts in LuaBindingsDispatchers.cpp LuaBindingsInternal.hpp LuaBindingsInternal.cpp | config/lua: reject excess arguments to dispatcher factories |
| 9f3facf61 | later: conflicts in main.cpp PointerManager.cpp CursorManager.cpp | cursor: store per-monitor images for cursor themes (#16439) |
| a3aee8276 | later: conflicts in main.cpp popup-render.cpp Compositor.cpp WindowEffectsController.cpp WindowEffec | renderer/workspace: add workspace presentable for passing workspace data to window rendering (#16440) |
| 586c01e69 | already in master | protocols/xdg-shell: fix initial commit not being reset (#16444) |
| aed4830ef | later: conflicts only in tests or build files | xwayland/xwm: don't reflect imported clipboards (#16445) |
| a9aad0cff | later: conflicts in hyprctl.bash hyprctl.fish hyprctl.usage hyprctl.zsh | hyprctl: remove shell completions (#16419) |
| c6e668757 | by hand: workspace_back_and_forth as 0/1/2, the rest later | config: fix on_current_monitor (#14615) |
| 212902547 | in master through the port branch | screenshare: fix potential crash on stale monitors (#16451) |
| 1c4fbb656 | already in master | config/lua: fix minor typo in mouseResize (#16454) |
| b1855f5c9 | in master through the port branch | protocols/input-capture: don't leak the eis fd (#16453) |
| e77e025de | already in master | config/actions: unfocus the last window properly on silent move away (#16452) |
| fed60b105 | already in master | layout/scrolling: scroll inhibitor also applies to `adjustOffset()` (#16434) |
| 90fb06e1e | later: conflicts only in tests or build files | desktop/ls: take keyboard focus away from constraints for exclusive (#16455) |
| 8e9a538fb | already in master | desktop/x11: fix modal check (#16456) |
| ae50c4d6b | later: conflicts in CMakeLists.txt CMakeLists.txt CMakeLists.txt | build: first batch of patches for OpenBSD support (#16457) |
| 150debcf6 | later or ignore: renderer/output conflicts | render: make frame options and results explicit |
| 969b4b111 | later: conflicts in main.cpp Compositor.cpp ColorManagement.cpp CursorshareSession.cpp ScreenshareFr | render: own transient state in a reusable render context |
| ba616caa9 | later: conflicts in main.cpp Overlay.cpp WindowEffectsController.cpp WindowEffectsController.hpp Ove | render: pass context explicitly through scene and draw APIs |
| 198dbec0c | later: conflicts in Context.cpp Context.hpp ElementRenderer.cpp OpenGL.cpp OpenGL.hpp Renderer.cpp R | render: scope nested draw state and framebuffer bindings |
| bcb5b7d8d | later or ignore: renderer/output conflicts | render: track sampled buffers per submission |
| 299ea94fe | later: conflicts in Renderer.cpp Renderer.hpp DMABUF.cpp | render: guard monitor reentry and test begin failure cleanup |
| ce87496c1 | later or ignore: renderer/output conflicts | render: share zoom calculation with tearing eligibility |
| 7c3e8b530 | later: conflicts in main.cpp WindowEffectsController.hpp EventBus.hpp ScreenshareFrame.cpp Notificat | all: update formatting for clang 23 |
| e5053fcda | already in master | desktop/tags: fix tag unmatching (#16474) |
| 9dc5398d1 | ignore: only touches code Hypoland removed | flake.lock: update, glibc breakage (#16462) |
| e92e2b4ea | picked | render: define explicit workspace scene selection |
| 592b33e3b | later or ignore: renderer/output conflicts | render: separate workspace membership from monitor composition |
| 23c56e078 | later: conflicts in Renderer.cpp Renderer.hpp SceneSelection.cpp SceneSelection.hpp SceneSelection.c | render: scope workspace fadeouts by snapshot origin |
| 96b5327d9 | picked (the port branch of 2026-10-28) | desktop: track floating offset origin |
| 2fb734cbf | later: conflicts in main.cpp Window.cpp Window.hpp WindowEffectsController.cpp WindowEffectsControll | render: resolve presentation before building draw passes |
| 78865f6b8 | later: conflicts in main.cpp popup-render.cpp WindowPresentation.cpp WindowPresentation.hpp Renderer | render: isolate workspace presentation from switch and transfer animations |
| ca539d4fb | later or ignore: renderer/output conflicts | render: select scene resources per render session |
| 74095c806 | later: conflicts in Context.cpp ElementRenderer.cpp OpenGL.cpp Renderer.cpp Renderer.hpp SceneResour | render: route preblur caches through scene resources |
| ea3578129 | later: conflicts in GLRenderer.cpp OpenGL.cpp OpenGL.hpp Renderer.cpp Renderer.hpp SceneResources.cp | render: isolate scratch attachments and output bookkeeping |
| 0475be0b2 | later or ignore: renderer/output conflicts | render: sample live blur material state without mutation |
| 8cc157948 | later or ignore: renderer/output conflicts | render: sample material clocks without advancing live state |
| cfb76b2c8 | later: conflicts only in tests or build files | hyprtester: cover isolated scene resource routing |
| bc82253e5 | later or ignore: renderer/output conflicts | renderer: clear stale HDR metadata (#16443) |
| 579829f06 | picked | clang-tidy: update for new clang (#16483) |
| db062ed2b | picked (the port branch of 2026-10-28) | macros: use __VA_OPT__ instead of GNU ##__VA_ARGS__ in RASSERT (#16487) |
| 19fb395d4 | ignore: only touches code Hypoland removed | [gha] Nix: update inputs |
| 5a78b5e92 | later: conflicts only in tests or build files | keybinds: fix shadowing and matching of multi-key binds (#16470) |
| 5e04ae1f9 | later: conflicts in main.cpp layer.cpp default.nix ConfigActions.cpp FocusState.cpp SeatManager.cpp  | desktop/constraint: move to controller and state (#16494) |
| 663b29b84 | already in master | config/lua: fix segfault on non-string errors (#16505) |
| 6a1b5f0fb | already in master | renderer: fix blur missing xray on fadeout (#16524) |
| 6cc0822e2 | ignore: only touches code Hypoland removed | nix: makeWrapper -> makeBinaryWrapper |
| 1bd31aaa5 | later: conflicts in  | fullscreen/scrolling: scrolling default handled fullscreen position sync upon work area change (#16493) |
| 80013b515 | ignore: only touches code Hypoland removed | ci/vouch: add exemption for certain PRs (#16502) |
| 40f96e0f8 | ignore: only touches code Hypoland removed | hyprpm: do not skip update when abi mismatches (#16540) |
| 38a82a411 | later: conflicts in ConfigManager.hpp ConfigManager.cpp ConfigManager.hpp | Make group-lock dispatchers behave more sensibly (#16231) |
| e2d94f54f | later: conflicts in  | desktop/window: Fix a few cursor focus losses (#15607) |
| a554bac46 | already in master | xwayland/xwm: fix overflow in handleWMHints (#16546) |
| 7b5b0c192 | already in master | seat: reject new grabs when the session is locked (#16547) |
| e2ad066c9 | ignore: only touches code Hypoland removed | nix: dedup inputs, update flake.lock (#16549) |
| 6c6ec3acc | later: conflicts in FsUtils.cpp | helpers/fs: adhere to XDG spec and small refactor (#16514) |
| 3633316a6 | already in master | layout/target: fix placement of floating X11 windows with positions at 0,0 (#16336) |
| 41287b665 | picked (the port branch of 2026-10-28) | helpers: complete YUV format detection |
| 9ff04c21b | picked (the port branch of 2026-10-28) | render: stop advertising unsupported YUV formats |
| 2f080fe46 | picked | build: second batch of patches for OpenBSD support (#16495) |
| 25f09b26f | later: conflicts in lua_config.cpp ConfigManager.cpp LuaBindingsToplevel.cpp LuaEventHandler.cpp | config/lua: centralize lua ref ownership (#16528) |
| 8010b4e5c | later: conflicts in CursorshareSession.cpp | screenshare: fix crash in cursor capture after monitor removal (#16533) |
| 121f29704 | ignore: colour management is removed | cm: don't advertise HDR headroom on SDR presets (#16525) |
| f6e3a723a | ignore: only touches code Hypoland removed | [gha] Nix: update inputs |
| 12f242511 | already in master | utils/fs: fix lookup logic and small refactor (remove redundant std::filesystem calls) (#16580) |
| b04e606a4 | picked (the port branch of 2026-10-28) | desktop/window: remove incorrect check, fix tearing (#16572) |
| 2860d07b0 | ignore: only touches code Hypoland removed | [gha] Nix: update inputs |
| afd025a59 | later: conflicts in Touch.cpp | input/touch: fix build on clang (#16605) |
| 815e3a822 | picked, its tests left out (foot, no plugin) | core/layers: top layers go below fullscreen windows, fix DS solitary (#15937) |
| 38e897f2b | picked (the port branch of 2026-10-28) | tests/lua: cover expired keybind handles (#16548) |
| 8b82ce5ff | picked | config/lua: add window.update_state (#16527) |
| c7216a980 | later or ignore: renderer/output conflicts | render/decoration: fix missing overrides (#16609) |
| 7d4682c94 | later: conflicts in CMakeLists.txt ScreenshareFrame.cpp ScreenshareManager.cpp ScreenshareManager.hp | protocols/workspace-icc: implement workspace ICC plumbing |
| 255fb40bb | later: conflicts in ScreenshareManager.cpp WorkspaceCaptureSource.cpp WorkspaceCaptureSource.hpp Wor | screenshare: expose workspace capture identity and snapshot demand |
| 96b7d6d4a | later: conflicts in MonitorResources.hpp WorkBufferPool.cpp WorkBufferPool.hpp OpenGL.cpp Renderer.c | render: support explicit isolated scene formats |
| 5226dfea8 | later: conflicts in Fadeout.cpp Fadeout.hpp PopupFadeout.cpp Renderer.cpp SceneSelection.cpp SceneSe | render: include output-pinned windows in workspace shell scenes |
| ed7e9570e | later or ignore: renderer/output conflicts | render: select workspace popups independently of input visibility |
| b5dd50d0f | later: conflicts in Fadeout.hpp PopupFadeout.cpp WindowFadeout.cpp Context.cpp Context.hpp Renderer. | render: exclude protected content from capture scenes |
| c5740aae2 | later: conflicts in WindowFadeout.cpp Renderer.cpp Renderer.hpp WindowRenderPresentation.cpp WindowR | render: retain neutral snapshots for workspace capture fadeouts |
| d38f92852 | later or ignore: renderer/output conflicts | render: preserve transparent backdrops through shader blur |
| 5849f3ebb | later: conflicts in ScreenshareFrame.cpp ScreenshareManager.hpp WorkspaceCaptureSession.cpp | protocols/workspace-icc: render selected workspace scenes |
| 74b3f1b52 | later: conflicts in action.yml .gitmodules CMakeLists.txt hyprland-protocols | cmake: remove h-p subproject, always use packaged |
| 85fae4675 | ignore: colour management is removed | cm: preserve scRGB encoding for internal linear buffers |
| 19a77ea94 | later: conflicts only in tests or build files | cm: honor luminances for parametric ext_linear descriptions |
| c7932c6ef | picked (the port branch of 2026-10-28) | core/output: install cleanup handlers for inert resources |
| 5b6b75ac5 | later: conflicts in Output.cpp Output.cpp | core/output: make late bindings to removed outputs inert |
| 2932e974d | later: conflicts in XDGOutput.cpp Output.cpp | xdg-output: handle requests for removed outputs |
| 8b7aefe32 | later: conflicts only in tests or build files | output-power: fail requests for unavailable outputs |
| 55e9805d7 | later: conflicts in ConfigManager.cpp ConfigManager.hpp LuaEventHandler.cpp LuaBindingsToplevel.cpp  | config/lua: unify lua callback calls (#16578) |
| 7c5226df4 | picked (the port branch of 2026-10-28) | core/tests: fix sporadically failing test, add helper to get window id (#16615) |
| 5a97e150a | later: conflicts only in tests or build files | core/tests: improve some layer tests (#16616) |
| 9ba363e05 | later: conflicts in flake.lock StringUtils.hpp StringUtils.cpp | window: utf8 truncate received window metadata (#16624) |
| 915d8a50c | picked (the port branch of 2026-10-28) | state/monitor: fix floating client losing remembered position monitor reconnect - cont. of #16569 (#16596) |
| 18ddac192 | picked (the port branch of 2026-10-28) | desktop/fadeout: reject finished and orphaned fadeouts |
| 76edafffc | picked (the port branch of 2026-10-28) | desktop/fadeout: collect completed snapshots after animation ticks |
| 171c93933 | picked (the port branch of 2026-10-28) | protocols/datadevice: fix nullable resource crashing (#16625) |
| bd7792adc | picked | config/mgr: return ptrs to setByUser |
| 875fa1743 | picked | config/value: provide setByUser() for checking value setness |
| ea288f9c1 | picked | config: implement redirectableConfigValue |
| 66ab80a6a | picked | tests: cover redirectable config values |
| a1c2428f7 | later: conflicts only in tests or build files | layout/scrolling: fix inconsistent column widths at tape edges, misc improvements (#16581) |
| b8cec477f | picked | render/blur: remove dead code (#16642) |
| 390f8f829 | ignore: only touches code Hypoland removed | codeowners: add erstarr to scrolling layout (#16634) |
| c9f4350e8 | picked (the port branch of 2026-10-28) | input: add swallowing focus click (#16250) |
| c4e7596a3 | ignore: needs the workspace refactor (created_early emitted by a shim) | config/lua: `created` to `created_early`, new `created` after setup is done; fix `on_created_empty` rule (#162 |
| 6cd467693 | by hand: the blur shader is GLES 2 here | renderer/shaders: add decoration:blur:proportional (#16643) |
| 26d9b5c27 | later: conflicts in Manager.cpp | protocols: implement xx-hotkey-v1 (#16407) |
| fb6e53802 | by hand: follow_focus 0/1/2 on Hypoland's focus reasons | layout/scrolling: make click behaviour when `follow_focus != 0` configurable (#16641) |
| a27cfea8d | later: conflicts in workspaces.cpp Monitor.cpp | core/workspace: fix workspace last focused window refocusing on change (#16675) |
| f46935176 | later: conflicts only in tests or build files | input: fix monitor focus not respecting `input:follow_mouse` (#16060) |
| e12c2e1ad | picked, its tests left out | config: add `layers` config category, move 2 config options from `misc` to there. (#16617) |
| f80e4dc2d | picked, its test client left out | core/fullscreen: ability to customise fs handler of a client requested fullscreen (#16635) |
| b957624c9 | later: conflicts in .clang-format WindowRuleApplicator.cpp Commands.cpp ColorManagement.cpp OpenGL.c | all: clang-format code (#16671) |
| db67c4938 | picked (the port branch of 2026-10-28) | compositor: set bits for all double buffered commits |
| 15659ff5a | picked (the port branch of 2026-10-28) | compositor: unmap null buffer commits |
| 380ebee15 | picked (the port branch of 2026-10-28) | tests: cover reopening a reused wl_surface |
| d70b097a6 | picked (the port branch of 2026-10-28) | compositor: limit fallback null-buffer unmaps to unassigned surfaces |
| f4f3d6f79 | picked (the port branch of 2026-10-28) | subcompositor: invalidate parent commits for placement changes |
| b3fd5b498 | picked (the port branch of 2026-10-28) | input-method: avoid dirtying popup state for rectangle notifications |
| 53759b8b3 | later or ignore: renderer/output conflicts | cm: refactor HDR preset descriptions into getHDRImageDescription() |
| aabab87c3 | later: conflicts in Monitor.hpp ColorManagement.cpp Compositor.cpp | cm: offer HDR to a fullscreen surface as the auto HDR trigger |
| 0aa6745f7 | later: conflicts in VERSION | VERSION: bump to 0.57.0 |

- 90 later
- 29 ignore
- 28 picked (the port branch of 2026-10-28)
- 23 already in master
- 19 later or ignore
- 18 picked
- 3 in master through the port branch
- 3 by hand
