PowerShell -Command "Set-ExecutionPolicy Unrestricted" >> "%TEMP%\StartupLog.txt" 2>&1
PowerShell C:\spellbreak-base-files\startup.ps1 >> "%TEMP%\StartupLog.txt" 2>&1