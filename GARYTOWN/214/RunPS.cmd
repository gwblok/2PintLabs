REM - this CMD file checks the platform (x86/64) and then runs the correct PS command line


PUSHD %~dp0
If "%PROCESSOR_ARCHITEW6432%"=="AMD64" GOTO 64bit
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command ".\StifleR_Client_Wrapper214.ps1"
GOTO END
:64bit
"%WinDir%\Sysnative\windowsPowershell\v1.0\Powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command ".\StifleR_Client_Wrapper214-ConfigMgr.ps1"
:END
POPD

