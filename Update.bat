@echo off
title Chris's Dungeon Macro Classic - Update
cd /d "%~dp0"
echo.
echo  Chris's Dungeon Macro Classic - updater
echo  ----------------------------------------
echo  Close the macro before updating.
echo  Your Settings and Logs folders are kept (your own walks, spots and options).
echo.
set "OLDVER=unknown"
if exist version.txt set /p OLDVER=<version.txt
echo  Current version: %OLDVER%
echo.
pause
echo  Downloading the newest version...
set "TMPZIP=%TEMP%\cdm-classic.zip"
set "TMPDIR=%TEMP%\cdm-classic"
if exist "%TMPDIR%" rmdir /s /q "%TMPDIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing 'https://github.com/ChickenChris/chris-dungeon-macro-classic/archive/refs/heads/main.zip' -OutFile $env:TMPZIP; Expand-Archive -LiteralPath $env:TMPZIP -DestinationPath $env:TMPDIR -Force"
if errorlevel 1 goto failed
if not exist "%TMPDIR%\chris-dungeon-macro-classic-main\Chris's Dungeon Macro.ahk" goto failed
echo  Installing...
robocopy "%TMPDIR%\chris-dungeon-macro-classic-main" "%~dp0." /E /XD Settings Logs .git /XF Update.bat .gitattributes .gitignore README.md /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto failed
rmdir /s /q "%TMPDIR%" 2>nul
del "%TMPZIP%" 2>nul
set "NEWVER=unknown"
if exist version.txt set /p NEWVER=<version.txt
echo.
echo  Done! Updated from %OLDVER% to %NEWVER%.
echo  Start "Chris's Dungeon Macro.ahk" again.
echo.
pause
exit /b 0

:failed
echo.
echo  The update didn't work. Check your internet connection and try again,
echo  or download the newest zip from the Discord server.
echo.
pause
exit /b 1
