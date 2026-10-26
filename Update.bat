@echo off
title Chris's Dungeon Macro Classic - Update
cd /d "%~dp0"
rem everything you see is drawn by Lib\Updater.ps1, so it can change with updates (this file can't)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Lib\Updater.ps1" -Full
exit /b %errorlevel%
