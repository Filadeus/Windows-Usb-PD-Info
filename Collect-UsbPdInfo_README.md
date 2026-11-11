# Collect-UsbPdInfo.ps1: how to use it and read the output

This script is a read-only diagnostic tool for the HP EliteBook 840 G11. It collects the USB-C / Power Delivery (PD) data that Windows and the HP BIOS have. Use this data together with the Power-Z captures. The script makes no changes to the system.

## How to run the script

1. Copy `Collect-UsbPdInfo.ps1` to the laptop, for example to `C:\Temp`.
2. Open **PowerShell as Administrator**. Without administrator rights, the script does not make the sleep study (file 08).
3. Run these commands:

   ```
   cd C:\Temp
   powershell -ExecutionPolicy Bypass -File .\Collect-UsbPdInfo.ps1 -HoursBack 24
   ```

   `-HoursBack` sets the age limit of the event log entries that the script reads (the default is 24 hours). Set it so that the time window includes your test session.
4. The script writes the results to a new folder next to the script: `UsbPdInfo_<yyyyMMdd_HHmmss>`.

**Recommended procedure:**

- Run the script immediately after a test session, after a failure or a success.
- Each time you start a Power-Z recording, write down the clock time and the laptop state (awake or asleep, battery %, on battery or charging).
- Power-Z capture times start at 0 at the start of each recording. Thus you need the clock time of the start to compare a capture with the Windows logs.

## Output files

| File | Contents | What to look for |
|---|---|---|
| `01_system.txt` | Model, SKU, BIOS version and date | Compare the BIOS version with the latest version on the HP support page for the 840 G11 |
| `02_hp_bios_usb_power.txt` | HP BIOS settings for USB, Type-C, power, charging, battery, sleep and firmware, with their possible values | See "Important BIOS settings" below |
| `02_hp_bios_all.txt` | All HP BIOS settings with their current values | Keep it for reference or for HP support |
| `02_hp_bios_ERROR.txt` | The script makes this file only if the HP WMI interface is not available | Normal on computers that are not from HP. On the HP, it means that the HP BIOS WMI provider is missing |
| `03_ucm_devices.txt` | USB-C connector manager, UCSI, Thunderbolt/USB4 and USB devices, with their status | The **UCM-UCSI ACPI Device** must show `OK`. `Error` or `Unknown` means that Windows cannot communicate correctly with the PD controller |
| `03_ucm_drivers.txt` | Driver versions and dates for those devices | Give these driver versions to HP support. Look for newer versions from HP |
| `04_available_logs.txt` | The USB / UCSI / power event logs on the system, and the number of entries in each log | Shows that `Microsoft-Windows-USB-UCMUCSICX/Operational` exists |
| `05_log_<name>.csv` | Events from each of those logs in the `-HoursBack` window | See "Reading the UCSI log" below |
| `06_power_timeline.csv` | Sleep, wake, Modern Standby and AC/battery events from the System log | Compare them with the Power-Z capture times (see below) |
| `07_battery_report.html` | Windows battery report: capacity, wear, and charge and discharge sessions | Shows if the laptop charged during a test, and the battery wear |
| `08_sleepstudy.html` | Modern Standby sessions for the last 3 days (needs administrator rights) | Shows when the laptop was asleep. This explains captures from a sleep period |
| `09_sleep_states.txt` | Supported sleep states (`powercfg /a`) | "Standby (S0 Low Power Idle)" means that the laptop uses Modern Standby |

Open the `.csv` files in Excel, or in PowerShell with `Import-Csv <file> | Out-GridView`.

## Important BIOS settings (`02_hp_bios_usb_power.txt`)

The names of the settings are different in different BIOS versions. Look for entries like these:

- **USB Type-C Controller(s) Firmware Version:** the PD controller firmware. Give this version in each HP support case. Look for updates from HP.
- **USB Type-C Connector System Software Interface (UCSI):** this setting must be on. If it is off, Windows cannot see the PD controller.
- **Charging and power-sharing options**, for example "USB charging port", "Charge in sleep/off" or "Power delivery". These settings control if the laptop *offers power* on its ports. The awake laptop offers power on its ports, and the awake laptop is the state in which the negotiations failed.
- **Battery Health Manager** or similar ("Maximize my battery health", "Let HP manage my battery charging"): these settings can stop or decrease charging at about 80–90%. This explains a very low charging current near full charge.
- **Sleep, Modern Standby and wake options:** the port behaviour can be different when the laptop is asleep and when it is awake.

## Reading the UCSI log (`05_log_Microsoft-Windows-USB-UCMUCSICX_Operational.csv`)

This file is the log of the Windows driver for the USB-C/PD controller.

- Each row has a time (`TimeCreated`), an event `Id`, a level and a message.
- Look for **errors or warnings near the times of failed captures**. Examples: command timeouts, "connector status" problems, or a PD controller that does not respond.
- Many events at the time of a plug-in are normal. Look for a *difference* between successful and failed plug-ins.
- An empty file means that Windows recorded no events in the time window. If necessary, run the script again with a larger `-HoursBack` value.

## Comparing with Power-Z captures (`06_power_timeline.csv`)

Useful event IDs:

| Id | Meaning |
|---|---|
| 1 | Woke from sleep (Power-Troubleshooter). The message gives the wake source |
| 42 | Entering sleep |
| 105 | Power source changed (AC ↔ battery). The message tells which |
| 107 | Resumed from sleep |
| 506 / 507 | Entering / leaving Modern Standby |
| 566 | Power state transition (Modern Standby session information) |

For each failed Power-Z capture, calculate its clock time. Then look at the events in this file just before that time. Examples:

- Did the laptop wake from Modern Standby a short time before the capture?
- Did the laptop change from AC to battery a short time before the capture?

A pattern such as "failures only within X minutes after a wake" or "failures only on battery" can show the laptop port mode.

## Recommended test routine

1. Connect only the Power-Z to the laptop, with nothing in the Power-Z female port. Record for about 10 s.
   - CC1/CC2 **stay at 0 V**: the laptop port is sink-only. Negotiation usually works in this state.
   - CC1/CC2 **change between about 3.2 V / 0.55 V and 0 V**: the laptop is in dual-role mode and offers power. Failures can occur in this state.
2. Connect the Sandberg powerbank and record the negotiation.
3. Write down the clock time, the laptop state and the battery %.
4. Do the test in each of these states:
   - Awake on battery, at high charge and at low charge.
   - After a wake from sleep.
   - After you disconnect a charger.
   - After a restart.
5. Run the script at the end. Keep the `UsbPdInfo_*` folder together with the related `.sqlite` captures.

## Privacy note

The output contains your computer model, BIOS fields about the serial number (in `02_hp_bios_all.txt`) and battery data. It does not contain personal files or PowerShell command history. Examine `02_hp_bios_all.txt` before you share it in public. It can contain the serial number and the asset tag. You can remove them.
