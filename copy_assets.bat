@echo off
echo Masaustu konumu: %USERPROFILE%\Desktop
echo OneDrive konumu: %USERPROFILE%\OneDrive\Masaustu
echo.
echo Masaustundeki FBX dosyalari:
dir "%USERPROFILE%\Desktop\*.fbx" 2>nul
dir "%USERPROFILE%\OneDrive\Masaustu\*.fbx" 2>nul
dir "D:\Desktop\*.fbx" 2>nul
echo.

mkdir "D:\Documents\proje-h\assets\characters" 2>nul

set SRC=
if exist "%USERPROFILE%\Desktop\Idle.fbx"            set SRC=%USERPROFILE%\Desktop
if exist "%USERPROFILE%\OneDrive\Masaustu\Idle.fbx"  set SRC=%USERPROFILE%\OneDrive\Masaustu

if "%SRC%"=="" (
    echo HATA: Idle.fbx bulunamadi. Asagidaki klasorlere bakildi:
    echo   %USERPROFILE%\Desktop
    echo   %USERPROFILE%\OneDrive\Masaustu
    echo.
    echo Lutfen FBX dosyalarinin tam yolunu yapistirin:
    set /p SRC="Klasor yolu: "
)

echo Kaynak: %SRC%
copy "%SRC%\Idle.fbx"                  "D:\Documents\proje-h\assets\characters\Idle.fbx"
copy "%SRC%\Catwalk Idle 01.fbx"       "D:\Documents\proje-h\assets\characters\Catwalk Idle 01.fbx"
copy "%SRC%\Walking (1).fbx"           "D:\Documents\proje-h\assets\characters\Walking.fbx"
copy "%SRC%\Breathing Idle.fbx"  "D:\Documents\proje-h\assets\characters\Breathing Idle.fbx"
copy "%SRC%\Sitting Idle.fbx"    "D:\Documents\proje-h\assets\characters\Sitting Idle.fbx"
copy "%SRC%\Laying Idle.fbx"     "D:\Documents\proje-h\assets\characters\Laying Idle.fbx"

echo.
echo Kopyalanan dosyalar:
dir "D:\Documents\proje-h\assets\characters\"
pause
