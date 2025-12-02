@ 2>/dev/null # 2>nul & echo off & goto BOF

unknown_exit() {
:unknown 2>/dev/null
    echo Could not find binaries/Darktide.exe
    echo Was this installed in the wrong location?
    echo Check the install guide and make sure none of these are missing:
    echo - binaries/
    echo - bundle/
    echo - launcher/
    echo - manifests/
    echo - mods/base/
    echo - mods/dmf/
    echo - mods/mod_load_order.txt
    echo - toggle_dt_mod_autopatch.cmd
@ 2>/dev/null # 2>nul & goto done
    exit
}

if [ ! -f "binaries/Darktide.exe" ]; then
    unknown_exit
fi

if [ -f "mods/DISABLE_AUTOPATCHER" ]; then
    rm mods/DISABLE_AUTOPATCHER
    echo Mods will be enabled when Darktide starts
    exit
else
    echo Darktide mod autopatching is disabled while this file exists>mods/DISABLE_AUTOPATCHER

    if grep -a "patch_999" bundle/bundle_database.data 1>/dev/null; then
        mv -f bundle/bundle_database.data.bak bundle/bundle_database.data
    fi

    echo Disabled mods
    exit
fi
exit

:BOF
if not exist "binaries\Darktide.exe" goto unknown

if exist "mods\DISABLE_AUTOPATCHER" goto enable
goto disable

:enable
del mods\DISABLE_AUTOPATCHER
echo Mods will be enabled when Darktide starts
goto done

:disable
echo Darktide mod autopatching is disabled while this file exists>mods\DISABLE_AUTOPATCHER

findstr patch_999 bundle\bundle_database.data 1>nul
if "%ERRORLEVEL%" == "0" move /y bundle\bundle_database.data.bak bundle\bundle_database.data >nul

echo Disabled mods
goto done

:done
REM check if running from cmd or gui
echo %CMDCMDLINE%|find "%~n0" 1>nul
if "%ERRORLEVEL%" == "0" goto gui
exit /B

:gui
echo:
pause
exit /B


:: hybrid cmd/sh script from https://stackoverflow.com/questions/17510688/_/48943532#48943532
