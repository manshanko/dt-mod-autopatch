dt-mod-autopatch
================

A Darktide plugin that patches `bundle_database.data` so mods can be loaded with [Darktide Mod Loader (DML)](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Loader/).

Based on Aussiemon's original nodejs script.

Supports Windows and Linux.

Implemented as a Darktide plugin `_dt_mod_autopatch.dll` is loaded everytime the game starts.
It then patches `bundle_database.data` to load `9ba626afa44a3aa3.patch_999` before Darktide starts loading bundles.

`toggle_dt_mod_autopatch.cmd` is a valid `cmd` and `sh` script for Windows and Linux that toggles dt-mod-autopatch.

## Build

Download [Zig 0.15](https://ziglang.org/download/#release-0.15.2) and build `_dt_mod_autopatch.dll` with `zig build --release=safe -Dtarget=x86_64-windows-gnu`
