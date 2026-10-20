PREFIX = /usr/local

stub:
	@echo "Do not run $(MAKE) directly without any arguments. Please refer to the wiki on how to compile Hyprland."

release:
	cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:STRING=${PREFIX} -S . -B ./build
	cmake --build ./build --config Release --target all -j`nproc 2>/dev/null || getconf NPROCESSORS_CONF`

debug:
	cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Debug -DTESTS=true -DCMAKE_INSTALL_PREFIX:STRING=${PREFIX} -S . -B ./build
	cmake --build ./build --config Debug --target all -j`nproc 2>/dev/null || getconf NPROCESSORS_CONF`

nopch:
	cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Release -DCMAKE_INSTALL_PREFIX:STRING=${PREFIX} -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON -S . -B ./build
	cmake --build ./build --config Release --target all -j`nproc 2>/dev/null || getconf NPROCESSORS_CONF`

clear:
	rm -rf build
	rm -f ./protocols/*.h ./protocols/*.c ./protocols/*.cpp ./protocols/*.hpp
	rm -f ./hyprctl/hw-protocols/*.cpp ./hyprctl/hw-protocols/*.hpp

all:
	$(MAKE) clear
	$(MAKE) release

install:
	cmake --install ./build

uninstall:
	xargs rm < ./build/install_manifest.txt

# pandoc writes into a temporary file, so a failed run leaves the man pages as they were
man:
	@command -v pandoc >/dev/null || { echo "make man needs pandoc"; exit 1; }
	pandoc ./docs/hypoland.1.rst \
		--standalone \
		--variable=header:"Hypoland User Manual" \
		--variable=date:"${DATE}" \
		--variable=section:1 \
		--from rst \
		--to man > ./docs/hypoland.1.tmp && mv ./docs/hypoland.1.tmp ./docs/hypoland.1 || { rm -f ./docs/hypoland.1.tmp; exit 1; }

	pandoc ./docs/hyprctl.1.rst \
		--standalone \
		--variable=header:"hyprctl User Manual" \
		--variable=date:"${DATE}" \
		--variable=section:1 \
		--from rst \
		--to man > ./docs/hyprctl.1.tmp && mv ./docs/hyprctl.1.tmp ./docs/hyprctl.1 || { rm -f ./docs/hyprctl.1.tmp; exit 1; }

asan:
	@echo -en "!!WARNING!!\nOnly run this in the TTY.\n"
	@pidof hypoland > /dev/null && echo -ne "Refusing to run with Hypoland running.\n" || echo ""
	@pidof hypoland > /dev/null && exit 1 || echo ""

	rm -rf ./wayland
	#git reset --hard

	@echo -en "If you want to apply a patch, input its path (leave empty for none):\n"
	@read patchvar; \
	 if [ -n "$$patchvar" ]; then patch -p1 < "$$patchvar" || echo ""; else echo "No patch specified"; fi

	git clone --recursive https://gitlab.freedesktop.org/wayland/wayland
	cd wayland && patch -p1 < ../scripts/waylandStatic.diff && meson setup build --buildtype=debug -Db_sanitize=address -Ddocumentation=false && ninja -C build && cd ..
	cp ./wayland/build/src/libwayland-server.a .
	@echo "Wayland done"

	patch -p1 < ./scripts/hyprlandStaticAsan.diff
	cmake --no-warn-unused-cli -DCMAKE_BUILD_TYPE:STRING=Debug -DWITH_ASAN:STRING=True -S . -B ./build
	cmake --build ./build --config Debug --target all
	@echo "Hyprland done"

	ASAN_OPTIONS="detect_odr_violation=0,log_path=asan.log" HYPRLAND_NO_CRASHREPORTER=1 ./build/hypoland -c ~/.config/hypr/hyprland.lua

format-check:
	@find src hyprctl start tests hyprtester -type f \( -name "*.cpp" -o -name "*.hpp" -o -name "*.h" \) \
		! -path "src/render/shaders/Shaders.hpp" \
		! -path "hyprctl/hw-protocols/*" \
		! -path "hyprtester/protocols/*" \
		| xargs clang-format --dry-run --Werror

format-fix:
	@find src hyprctl start tests hyprtester -type f \( -name "*.cpp" -o -name "*.hpp" -o -name "*.h" \) \
		! -path "src/render/shaders/Shaders.hpp" \
		! -path "hyprctl/hw-protocols/*" \
		! -path "hyprtester/protocols/*" \
		| xargs clang-format -i

test:
	$(MAKE) debug
	./build/hyprtester/hyprtester -c hyprtester/test.lua -b ./build/hypoland $(TESTS)
