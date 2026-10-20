:title: hyprctl(1)
:author: Vaxerski <*https://github.com/vaxerski*>

NAME
====

hyprctl - Utility for controlling parts of Hypoland from a CLI or a script

SYNOPSIS
========

**hyprctl** [*(opt)flags*] [**command**] [*(opt)args*]

DESCRIPTION
===========

**hyprctl** is a utility for controlling some parts of the compositor from a CLI or a script.

CONTROL COMMANDS
================

**dispatch**

    Call a dispatcher with an argument.

    An argument must be present.
    For dispatchers without parameters it can be anything.

    Returns: *ok* on success, and an error message on failure.

    Examples:
        **hyprctl** *dispatch "hl.dsp.exec_cmd('kitty')"*

        **hyprctl** *dispatch "hl.dsp.window.close()"*

**keyword**

    Not available: the config is Lua, the compositor answers *unknown request*. Use **eval** instead,
    e.g. *eval 'hl.config({ general = { border_size = 10 } })'*.

**eval**

    Evaluate arbitrary Lua expressions dynamically when using a Lua-based config provider.

    Returns: *ok* on success, and an error message on failure.

    Examples:
        **hyprctl** *eval 'hl.bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd("firefox"))'*

        **hyprctl** *eval 'hl.config({ general = { border_size = 10 } })'*

**reload**

    Force a reload of the config file.

**kill**

    Enter kill mode, where you can kill an app by clicking on it.
    You can exit by pressing ESCAPE.

INFO COMMANDS
=============

**version**

    Prints the version, flags, commit and branch of build. The text names Hyprland, for tools that read it.

**monitors**

    Lists all the outputs with their properties.

**workspaces**

    Lists all workspaces with their properties.

**clients**

    Lists all windows with their properties.

**devices**

    Lists all connected input devices.

**activewindow**

    Returns the active window name.

**layers**

    Lists all the layers.

**splash**

    Returns the current random splash.

**status**

    Returns internal status information like config format or backend.

OPTIONS
=======

**--batch**

    Specify a batch of commands to execute.

    Example:
        **hyprctl** *--batch "eval hl.config({ general = { border_size = 2 } }) ; eval hl.config({ general = { gaps_out = 20 } })"*

        *;* separates the commands.

**-j**

    Outputs information in JSON.

BUGS
====

Submit bug reports and request features online at:
    <*https://github.com/hegjon/hypoland/issues*>

SEE ALSO
========

**hypoland**\(1)

Sources at: <*https://github.com/hegjon/hypoland*>

COPYRIGHT
=========

Copyright (c) 2022, vaxerski
