# Fix: SSL error for network requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Add startup script
Register-ScheduledTask -TaskName "SpellbreakSupervisor" -Trigger (New-ScheduledTaskTrigger -AtStartup) -Action (New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\spellbreak-supervision\startup.ps1`"") -RunLevel Highest -Force -User "Administrator" -Password "SuperSpellBS3cr3t!!!!"

# Unzip Mod into g3\Content\Paks folder
Write-Host "Unzipping mod to g3\\Content\\Paks..."
Expand-Archive -LiteralPath "C:\\spellbreak-base-files\\balance-patch.zip" -DestinationPath "C:\\spellbreak-community-server\\g3\\Content\\Paks"

Write-Host "Installing dependency - psutil..."
C:\python312\python.exe -m pip install --upgrade pip
c:\python312\python.exe -m pip install psutil