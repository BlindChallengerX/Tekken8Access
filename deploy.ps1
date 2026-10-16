# Copy the built mod (out\TekkenA11y) into the game's UE4SS Mods folder.
# Keeps dev.txt if present. Close the game first (the helper exe is in use while it runs).
$src = Join-Path $PSScriptRoot 'out\TekkenA11y'
$dst = 'C:\Program Files (x86)\Steam\steamapps\common\TEKKEN 8\Polaris\Binaries\Win64\Mods\TekkenA11y'
Get-Process TekkenA11yHelper, TekkenA11ySpeech -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300
if (Test-Path "$dst\Scripts") { Remove-Item "$dst\Scripts" -Recurse -Force }
foreach ($old in 'speaker\TekkenA11ySpeech.exe', 'speaker\Tolk.dll', 'speaker\nvdaControllerClient64.dll', 'charselect_profiles.txt', 'dump.txt') {
    if (Test-Path "$dst\$old") { Remove-Item "$dst\$old" -Force }
}
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item "$src\*" $dst -Recurse -Force
Write-Output "deployed to $dst"
