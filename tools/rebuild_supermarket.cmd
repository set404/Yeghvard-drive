@echo off
rem Double-click to rebuild world\supermarket.scn (see rebuild_supermarket.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rebuild_supermarket.ps1"
