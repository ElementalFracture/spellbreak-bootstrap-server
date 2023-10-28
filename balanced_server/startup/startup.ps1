Start-Transcript -path C:\spellbreak-supervision\supervisor.log -append
Write-Output "Starting Spellbreak server!"
c:\python312\python.exe C:\spellbreak-supervision\GameServer.py
Write-Output "Stopping Spellbreak server!"
Stop-Transcript
