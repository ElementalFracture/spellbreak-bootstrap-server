[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$serverc = New-Object System.Net.WebClient;
$serverc.Headers.Add("User-Agent: Other");
$serverc.DownloadFile("https://sbreak-comm-files.s3.amazonaws.com/spellbreak-community-version-server-windows+(1).zip", "C:\\spellbreak-base-files\\community-server.zip")

Expand-Archive -LiteralPath "C:\\spellbreak-base-files\\community-server.zip" -DestinationPath "C:\\spellbreak-community-server"

$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$Home\Desktop\spellbreak-community-server.lnk")
$Shortcut.TargetPath = "C:\\spellbreak-community-server"
$Shortcut.Save()