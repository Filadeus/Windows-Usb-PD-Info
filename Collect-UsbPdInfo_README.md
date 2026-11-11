# Collect-UsbPdInfo.ps1: how to use it and read the output

This is a read-only diagnostic script for the HP EliteBook 840 G11. It gathers what Windows and the HP BIOS know about the USB-C / Power Delivery (PD) side of the laptop, so you can line it up with Power-Z captures. It changes nothing on the system.

## Running it

1. Copy `Collect-UsbPdInfo.ps1` to the laptop, for example to `C:\Temp`.
2. Open **PowerShell as Administrator**. Without admin rights, the sleep study (file 08) is skipped.
3. Run:

   ```
   cd C:\Temp
   powershell -ExecutionPolicy Bypass -File .\Collect-UsbPdInfo.ps1 -HoursBack 24
   ```

   `-HoursBack` sets how far back the event logs are read (the default is 24). Set it so the window covers your test session.
4. Results go to a new folder next to the script: `UsbPdInfo_<yyyyMMdd_HHmmss>`.

**Best practice:** run it right after a test session, failed or successful, while the events are fresh. Each time you start a Power-Z recording, write down the wall-clock time and the laptop's state (awake/asleep, battery %, on battery or charging). Power-Z capture times start at 0 when the recording starts, so you need the wall-clock start time to match a capture against the Windows logs.

## Output files

| File | What it contains | What to look for |
|---|---|---|
| `01_system.txt` | Model, SKU, BIOS version and date | Compare the BIOS version with the latest on HP's support page for the 840 G11 |
| `02_hp_bios_usb_power.txt` | HP BIOS settings related to USB, Type-C, power, charging, battery, sleep and firmware, with their possible values | See "Important BIOS settings" below |
| `02_hp_bios_all.txt` | Every HP BIOS setting with its current value | Keep it for reference or for HP support |
| `02_hp_bios_ERROR.txt` | Only created if the HP WMI interface isn't available | Normal on non-HP machines. On the HP, it means the HP BIOS WMI provider is missing |
| `03_ucm_devices.txt` | USB-C connector manager, UCSI, Thunderbolt/USB4 and USB devices, with their status | The **UCM-UCSI ACPI Device** should be `OK`. `Error` or `Unknown` means Windows can't talk to the PD controller properly |
| `03_ucm_drivers.txt` | Driver versions and dates for those devices | Driver versions to quote to HP support; check whether HP offers newer ones |
| `04_available_logs.txt` | Which USB / UCSI / power event logs exist and how many entries each has | Confirms that `Microsoft-Windows-USB-UCMUCSICX/Operational` exists |
| `05_log_<name>.csv` | Events from each of those logs within the `-HoursBack` window | See "Reading the UCSI log" below |
| `06_power_timeline.csv` | Sleep, wake, Modern Standby and AC/battery events from the System log | Line them up with Power-Z capture times, see below |
| `07_battery_report.html` | Windows battery report: capacity, wear, and charge and discharge sessions | Shows whether charging actually happened during a test, and battery wear |
| `08_sleepstudy.html` | Modern Standby sessions for the last 3 days (needs admin) | Shows when the laptop was asleep, which explains captures taken during sleep |
| `09_sleep_states.txt` | Supported sleep states (`powercfg /a`) | "Standby (S0 Low Power Idle)" means the laptop uses Modern Standby |

Open the `.csv` files in Excel, or in PowerShell with `Import-Csv <file> | Out-GridView`.

## Important BIOS settings (`02_hp_bios_usb_power.txt`)

Exact names vary between BIOS versions. Look for entries like these:

- **USB Type-C Controller(s) Firmware Version**: the PD controller firmware. Quote it in any HP support case and check HP for updates.
- **USB Type-C Connector System Software Interface (UCSI)**: should be enabled. If it's disabled, Windows has no visibility into the PD controller.
- **Charging / power-sharing options**, for example "USB charging port", "Charge in sleep/off" or "Power delivery". These control whether the laptop *offers power* on its ports. Offering power is the dual-role behaviour linked to the failed negotiations.
- **Battery Health Manager** or similar ("Maximize my battery health", "Let HP manage my battery charging"): these can stop or slow charging around 80–90%. That explains a very small charging current near full charge.
- **Sleep / Modern Standby / wake options**: the port behaviour may differ between sleep and awake.

## Reading the UCSI log (`05_log_Microsoft-Windows-USB-UCMUCSICX_Operational.csv`)

This is the log of Windows' driver for the USB-C/PD controller.

- Each row has a time (`TimeCreated`), an event `Id`, a level and a message.
- Look for **errors or warnings near the times of failed captures**. Examples: command timeouts, "connector status" problems, or the PD controller not responding.
- A burst of events at plug-in time is normal. What matters is a *difference* between successful and failed plug-ins.
- An empty file just means no events were logged in the time window. Re-run with a larger `-HoursBack` if needed.

## Lining up with Power-Z captures (`06_power_timeline.csv`)

Useful event IDs:

| Id | Meaning |
|---|---|
| 1 | Woke from sleep (Power-Troubleshooter; the message gives the wake source) |
| 42 | Entering sleep |
| 105 | Power source changed (AC ↔ battery); the message says which |
| 107 | Resumed from sleep |
| 506 / 507 | Entering / leaving Modern Standby |
| 566 | Power state transition (Modern Standby session info) |

For each failed Power-Z capture, work out its wall-clock time and check what happened just before it in this file. For example: did the laptop just wake from Modern Standby, or just switch from AC to battery? A pattern like "failures only within X minutes after waking" or "only while on battery" is the kind of evidence that points to the laptop's port mode.

## Recommended test routine

1. Plug the Power-Z alone into the laptop, with nothing in its female port, and record for about 10 s.
   - CC1/CC2 **steady 0 V**: the laptop port is sink-only, and negotiation is expected to work.
   - CC1/CC2 **flicking between about 3.2 V / 0.55 V and 0 V**: the laptop is in dual-role mode, offering power. This is the failure-prone state.
2. Connect the Sandberg powerbank and record the negotiation.
3. Note the wall-clock time, laptop state and battery %.
4. Repeat across states: awake on battery at high and low charge, after waking from sleep, after unplugging a charger, after a restart.
5. Run the script at the end, and keep the `UsbPdInfo_*` folder with the matching `.sqlite` captures.

## Privacy note

The output contains your machine model, serial-related BIOS fields (in `02_hp_bios_all.txt`) and battery details, but no personal files and no PowerShell command history. Check `02_hp_bios_all.txt` before sharing it publicly. It can contain the serial number and asset tag, which you can remove.
