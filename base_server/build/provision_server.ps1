# Download Spellbreak Community Server files
Write-Host "Downloading Spellbreak Community Server..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$serverc = New-Object System.Net.WebClient;
$serverc.Headers.Add("User-Agent: Other");
$serverc.DownloadFile("https://sbreak-comm-files.s3.amazonaws.com/spellbreak-community-version-server-windows+(1).zip", "C:\\spellbreak-base-files\\community-server.zip")
Write-Host "Spellbreak Downloaded."

# Unpack them to C:\spellbreak-community-server
Write-Host "Unzipping server files..."
Expand-Archive -LiteralPath "C:\\spellbreak-base-files\\community-server.zip" -DestinationPath "C:\\spellbreak-community-server"

# Make a shortcut on the desktop for easy access
Write-Host "Creating convenient desktop shorcut..."
New-Item -ItemType SymbolicLink -Target "C:\\spellbreak-community-server" -Path "$Home\Desktop\Spellbreak Community Server.lnk"

# Open Port 7777 (Spellbreak's default port)
Write-Host "Adding firewall rules to allow Spellbreak ports..."
netsh advfirewall firewall add rule name="Spellbreak (TCP)" dir=in action=allow protocol=TCP localport=7777
netsh advfirewall firewall add rule name="Spellbreak (UDP)" dir=in action=allow protocol=UDP localport=7777
