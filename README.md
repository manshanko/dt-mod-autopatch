dt-mod-autopatch
================

A Darktide plugin that patches `bundle_database.data` so mods can be loaded with [Darktide Mod Loader (DML)](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Loader/).

Based on Aussiemon's original nodejs script.

Supports Windows and Linux.

## About

dt-mod-autopatch is a Darktide plugin (`_dt_mod_autopatch.dll`) that patches `bundle_database.data` to load `9ba626afa44a3aa3.patch_999` from DML.

Since dt-mod-autopatch is loaded by Darktide the same binary works on Linux with Wine.
In addition `toggle_dt_mod_autopatch.cmd` is a hybrid `cmd`/`sh` script works on Windows and Linux.

## Build

Download [Zig 0.15](https://ziglang.org/download/#release-0.15.2) and build `_dt_mod_autopatch.dll` with `zig build --release=safe -Dtarget=x86_64-windows-gnu`
