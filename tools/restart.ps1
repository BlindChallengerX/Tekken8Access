# Close Tekken 8 if running, start it through Steam, wait until UE4SS has started the mods.
param([switch]$NoKill)
$log = 'C:\Program Files (x86)\Steam\steamapps\common\TEKKEN 8\Polaris\Binaries\Win64\UE4SS.log'
if (-not $NoKill) {
    Get-Process Polaris-Win64-Shipping, 'TEKKEN 8' -ErrorAction SilentlyContinue | Stop-Process -Force
    for ($i = 0; $i -lt 40 -and (Get-Process Polaris-Win64-Shipping -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    Start-Sleep 6
}
$start = Get-Date
for ($try = 0; $try -lt 3; $try++) {
    Start-Process 'steam://rungameid/1778820'
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep 2
        if ((Get-Item $log).LastWriteTime -gt $start -and (Select-String $log -Pattern 'Event loop start' -Quiet)) {
            Get-Content $log | Select-String '\[A11y\]' | ForEach-Object Line
            exit 0
        }
        if ($i -eq 15 -and -not (Get-Process Polaris-Win64-Shipping -ErrorAction SilentlyContinue)) { break }
    }
}
Write-Output 'game did not start'
exit 1
