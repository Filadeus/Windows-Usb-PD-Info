# Collect-UsbPdInfo.ps1  -  READ-ONLY diagnostics for USB-C / PD behaviour on the HP laptop.
# Run in an elevated PowerShell on the laptop:
#   powershell -ExecutionPolicy Bypass -File .\Collect-UsbPdInfo.ps1 [-HoursBack 24]
# Output: a folder UsbPdInfo_<timestamp> next to the script. Changes nothing on the system.
param([int]$HoursBack = 24)

$out = Join-Path $PSScriptRoot ("UsbPdInfo_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $out | Out-Null
$since = (Get-Date).AddHours(-$HoursBack)
function Save($name, $obj) { $obj | Out-File -Width 400 -FilePath (Join-Path $out $name) }

# 1. System / BIOS identity
Save "01_system.txt" (Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, SystemSKUNumber)
Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion, ReleaseDate | Out-File -Append -FilePath (Join-Path $out "01_system.txt")

# 2. HP BIOS settings via HP WMI (includes USB Type-C controller FW version on most models)
try {
    $hp = Get-CimInstance -Namespace root\HP\InstrumentedBIOS -ClassName HP_BIOSSetting -ErrorAction Stop
    Save "02_hp_bios_all.txt" ($hp | Sort-Object Name | Select-Object Name, @{n='Value';e={ if ($_.CurrentValue) { $_.CurrentValue } else { $_.Value } }} | Format-Table -AutoSize)
    Save "02_hp_bios_usb_power.txt" ($hp | Where-Object Name -match 'USB|Type-C|UCSI|Thunderbolt|Power|Charg|Battery|Sleep|Standby|Wake|Firmware' |
        Sort-Object Name | Select-Object Name, @{n='Value';e={ if ($_.CurrentValue) { $_.CurrentValue } else { $_.Value } }}, PossibleValues | Format-List)
} catch { Save "02_hp_bios_ERROR.txt" "HP WMI namespace not available: $_" }

# 3. USB-C connector manager / UCSI devices and drivers
Save "03_ucm_devices.txt" (Get-PnpDevice -ErrorAction SilentlyContinue |
    Where-Object { $_.Class -match 'UCM|USB' -or $_.FriendlyName -match 'UCSI|Connector|Type-C|Thunderbolt|USB4' } |
    Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize)
Save "03_ucm_drivers.txt" (Get-CimInstance Win32_PnPSignedDriver |
    Where-Object { $_.DeviceName -match 'UCSI|Connector|Type-C|Thunderbolt|USB4|PD' } |
    Select-Object DeviceName, DriverVersion, DriverDate, InfName | Format-Table -AutoSize)

# 4. Which event logs exist for USB / UCM / Type-C on this build
$logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.LogName -match 'USB|UCM|UCSI|TypeC|Type-C|Thunderbolt|Battery|Kernel-Power|Power-Troubleshooter' -and $_.LogName -notmatch 'PowerShell|TerminalServices' }
Save "04_available_logs.txt" ($logs | Select-Object LogName, IsEnabled, RecordCount | Format-Table -AutoSize)
foreach ($l in $logs | Where-Object { $_.RecordCount -gt 0 }) {
    $safe = ($l.LogName -replace '[\\/:*?"<>| ]', '_')
    Get-WinEvent -FilterHashtable @{LogName = $l.LogName; StartTime = $since} -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
        Export-Csv -NoTypeInformation -Path (Join-Path $out "05_log_$safe.csv")
}

# 5. Power-state timeline from the System log (sleep/wake, modern standby, AC/DC changes)
$ids = 1, 42, 105, 107, 506, 507, 566
Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = $since} -ErrorAction SilentlyContinue |
    Where-Object { $_.ProviderName -match 'Kernel-Power|Power-Troubleshooter|ACPI|UCM|USB' -and ($ids -contains $_.Id -or $_.ProviderName -match 'UCM|USB|ACPI') } |
    Select-Object TimeCreated, Id, ProviderName, @{n='Message';e={ ($_.Message -split "`n")[0] }} |
    Export-Csv -NoTypeInformation -Path (Join-Path $out "06_power_timeline.csv")

# 6. Standard power reports (HTML)
powercfg /batteryreport /output (Join-Path $out "07_battery_report.html") | Out-Null
powercfg /sleepstudy   /output (Join-Path $out "08_sleepstudy.html") /duration 3 | Out-Null
powercfg /a > (Join-Path $out "09_sleep_states.txt")

Write-Host "Done. Results in $out"
