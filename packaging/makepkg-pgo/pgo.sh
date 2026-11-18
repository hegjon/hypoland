#!/hint/bash
#
#   pgo.sh - profile guided builds with GCC, a makepkg plugin
#
#   Install as /usr/share/makepkg/buildenv/pgo.sh (makepkg sources every file there):
#     install -Dm644 pgo.sh /usr/share/makepkg/buildenv/pgo.sh
#
#   A package that supports it has `pgo` in its options=(). The plugin then adds flags to CFLAGS, CXXFLAGS and LDFLAGS
#   only when the environment asks for them, so a build without these variables is a plain one:
#     PGO_GENERATE=DIR  the instrumented build: its programs write their counters into DIR when they exit (DIR has to
#                       be writable by every user that runs them, threads update the counters atomically)
#     PGO_PROFILE=DIR   the build with the counters in DIR (several trainings merged with `gcov-tool merge`); a function
#                       without counters, or changed since the training, is compiled as without a profile
#     PGO_ORDER=FILE    links with FILE as the linker's section ordering file (GNU ld 2.43 or newer), e.g. the
#                       functions that ran in the training first; with or without a profile
#
#   The counter files are named after the object files' paths below $srcdir, so they do not depend on BUILDDIR. GCC
#   finds a function's counters by a checksum that has its source file's path in it, though: when a package compiles
#   sources from $srcdir (generated ones too), build with the profile in the same BUILDDIR as the training.
#   !buildflags turns it off with the other flags.

[[ -n "$LIBMAKEPKG_BUILDENV_PGO_SH" ]] && return
LIBMAKEPKG_BUILDENV_PGO_SH=1

MAKEPKG_LIBRARY=${MAKEPKG_LIBRARY:-'/usr/share/makepkg'}

source "$MAKEPKG_LIBRARY/util/message.sh"
source "$MAKEPKG_LIBRARY/util/option.sh"
source "$MAKEPKG_LIBRARY/util/util.sh"

build_options+=('pgo')
buildenv_functions+=('buildenv_pgo')

buildenv_pgo() {
	check_option "pgo" "y" && ! check_option "buildflags" "n" || return 0
	[[ -n $PGO_GENERATE || -n $PGO_PROFILE || -n $PGO_ORDER ]] || return 0

	local flags=() flag var
	if [[ -n $PGO_GENERATE && -n $PGO_PROFILE ]]; then
		error "$(gettext "%s and %s are both set")" "PGO_GENERATE" "PGO_PROFILE"
		exit 1
	elif [[ -n $PGO_GENERATE ]]; then
		flags=("-fprofile-generate=$PGO_GENERATE" -fprofile-update=prefer-atomic "-fprofile-prefix-path=$srcdir")
	elif [[ -n $PGO_PROFILE ]]; then
		if [[ ! -d $PGO_PROFILE ]]; then
			error "$(gettext "%s is no directory: %s")" "PGO_PROFILE" "$PGO_PROFILE"
			exit 1
		fi
		flags=("-fprofile-use=$PGO_PROFILE" -fprofile-correction -Wno-missing-profile "-fprofile-prefix-path=$srcdir")
	fi

	for flag in "${flags[@]}"; do
		for var in CFLAGS CXXFLAGS LDFLAGS; do
			append_once "$var" "$flag"
		done
	done

	if [[ -n $PGO_ORDER ]]; then
		if [[ ! -f $PGO_ORDER ]]; then
			error "$(gettext "%s is no file: %s")" "PGO_ORDER" "$PGO_ORDER"
			exit 1
		fi
		append_once LDFLAGS "-Wl,--section-ordering-file=$PGO_ORDER"
	fi
}
