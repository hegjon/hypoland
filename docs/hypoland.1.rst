:title: Hypoland
:author: Vaxerski <*https://github.com/vaxerski*> (Hyprland), Jonny Heggheim (Hypoland)

NAME
====

hypoland - Dynamic tiling Wayland compositor for OpenGL ES 2.0 graphics

SYNOPSIS
========

**hypoland** [*arg [...]*].

DESCRIPTION
===========

**Hypoland** is a fork of the Wayland compositor Hyprland for graphics hardware that is
limited to OpenGL ES 2.0, such as Intel GMA X3100 and GMA 4500MHD.

It is an independent project and not affiliated with or endorsed by Hyprland.

You can launch Hypoland by either going into a TTY and
executing **start-hypoland**, or with a login manager.

COMPATIBILITY
=============

Hypoland reads the configuration of Hyprland and answers on the same sockets, so configs and
tools made for Hyprland keep working.

Color management, HDR, motion blur, the logo background, the default wallpapers, plugins and
hyprpm are removed. Their config options are accepted and ignored. Blur, shadows, animations
and the splash text are off by default.

CONFIGURATION
=============

The configuration is read from *$XDG_CONFIG_HOME/hypr/hyprland.lua*.

For configuration information please see <*https://wiki.hypr.land*>.

OPTIONS
=======

**-h**, **--help**
    Show command usage.

**-c**, **--config** *FILE*
    Specify config file to use.

**--socket** *NAME*
    Sets the Wayland socket name (for Wayland socket handover)

**--wayland-fd** *FD*
    Sets the Wayland socket file descriptor (for Wayland socket handover)

**--watchdog-fd** *FD*
    Used by start-hypoland.

**--safe-mode**
    Starts Hypoland in safe mode.

**--systeminfo**
    Prints system infos.

**--i-am-really-stupid**
    Omits the check for root user privileges.

**--verify-config**
    Do not run Hypoland, only print if the config has any errors.

**-v**, **--version**
    Print the version.

**--version-json**
    Print the version as JSON.

**--locked-cmd** *COMMAND*
    Launches a locker on startup via the provided command.

BUGS
====

Submit bug reports and request features online at:
    <*https://github.com/hegjon/hypoland/issues*>

SEE ALSO
========

**hyprctl**\(1)

Sources at: <*https://github.com/hegjon/hypoland*>

COPYRIGHT
=========

Copyright (c) 2022, vaxerski

Hypoland is based on Hyprland and distributed under the same BSD 3-Clause license.
