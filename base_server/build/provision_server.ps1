# Fix: SSL error for network requests
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Download Spellbreak Community Server files
Write-Host "Downloading Spellbreak Community Server..."
New-Item -ItemType Directory -Path C:\spellbreak-base-files
New-Item -ItemType Directory -Path C:\spellbreak-supervision

$serverc = New-Object System.Net.WebClient;
$serverc.Headers.Add("User-Agent: Other");
$serverc.DownloadFile("https://sbreak-comm-files.s3.amazonaws.com/spellbreak-community-version-server-windows+(1).zip", "C:\\spellbreak-base-files\\community-server.zip")
Write-Host "Spellbreak Downloaded."

# Unpack them to C:\spellbreak-community-server
Write-Host "Unzipping server files..."
Expand-Archive -LiteralPath "C:\\spellbreak-base-files\\community-server.zip" -DestinationPath "C:\\spellbreak-community-server"

# Make a shortcut on the desktop for easy access
Write-Host "Creating convenient desktop shorcuts..."
New-Item -ItemType SymbolicLink -Target "C:\\spellbreak-community-server" -Path "$Home\Desktop\Spellbreak Community Server.lnk"
New-Item -ItemType SymbolicLink -Target "C:\\spellbreak-supervision" -Path "$Home\Desktop\Spellbreak Supervision.lnk"

# Open Port 7777 (Spellbreak's default port)
Write-Host "Adding firewall rules to allow Spellbreak ports..."
netsh advfirewall firewall add rule name="Spellbreak (TCP)" dir=in action=allow protocol=TCP localport=7777
netsh advfirewall firewall add rule name="Spellbreak (UDP)" dir=in action=allow protocol=UDP localport=7777

# Install Python
Write-Host "Downloading Chocolatey to install Python..."
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
refreshenv

Write-Host "Installing Python..."
choco install -y python312

Write-Host "Installing Elixir..."
choco install -y elixir