@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Kazeta + GCompris: Teile zusammenfuegen
for %%f in (kazeta-gcompris.img.xz.part-00 kazeta-gcompris.img.xz.part-01 kazeta-gcompris.img.xz.part-02) do (
  if not exist "%%f" (
    echo Die Datei %%f fehlt. Bitte alle drei Teile in diesen Ordner herunterladen.
    pause
    exit /b 1
  )
)
echo Fuege die drei Teile zusammen, das dauert etwa eine Minute ...
copy /b kazeta-gcompris.img.xz.part-00 + kazeta-gcompris.img.xz.part-01 + kazeta-gcompris.img.xz.part-02 kazeta-gcompris.img.xz >nul
if errorlevel 1 (
  echo Fehler beim Zusammenfuegen. Ist genug Speicherplatz frei (etwa 5 GB^)?
  pause
  exit /b 1
)
echo.
echo Fertig! Die Datei kazeta-gcompris.img.xz liegt jetzt in diesem Ordner.
echo Diese Datei in balenaEtcher mit "Flash from file" auswaehlen.
echo Die drei .part-Dateien koennen danach geloescht werden.
echo.
pause
