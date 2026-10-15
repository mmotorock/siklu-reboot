# Siklu Reboot

A small PowerShell script that reboots a pair of **Siklu** wireless radios (a point-to-point link) over SSH, in the correct order, and confirms that each device actually went offline. It is designed to be run unattended, e.g. from Windows Task Scheduler, so you can schedule regular reboots of the link.

## How it works

1. Connects via SSH to the **remote** radio (the far end of the link) and sends `reboot system`.
2. Pings the remote radio until it stops responding, confirming the reboot started.
3. Connects via SSH to the **local** radio (the end on your side of the link) and sends `reboot system`.
4. Pings the local radio until it stops responding.
5. Logs everything to `logs\reboot_log.txt` next to the script.

## ⚠️ Important: reboot order (remote first, then local)

The **remote** device **must** be rebooted **first**, and the **local** device second.

The moment the local radio reboots, the wireless link goes down - and with it, your only path to the remote radio. If the local device were rebooted first, the script would no longer be able to reach the remote device to send it the reboot command.

By rebooting the remote end first, the command reaches it while the link is still up. Once it is confirmed offline, the local device (which is still reachable directly on your network) is rebooted. Both ends then come back up and re-establish the link.

So when configuring the script, make sure:

- `RemoteIP` = the radio on the **far side** of the link
- `LocalIP` = the radio on **your side** of the link (the one you can reach without going over the wireless link)

## Requirements

- Windows with PowerShell 5.1 or later
- The OpenSSH client (`ssh.exe`) available on `PATH`, version 8.4 or newer (needed for `SSH_ASKPASS_REQUIRE`, which lets the script supply the password non-interactively). Check with `ssh -V`.
- SSH access enabled on both Siklu radios, and a user account permitted to run `reboot system`
- ICMP (ping) allowed to both radios from the machine running the script

## Configuration

Open `reboot-siklu.ps1` and replace the placeholder values at the top:

```powershell
param (
    [string]$RemoteIP = "type remote device IP here",
    [string]$LocalIP = "type local device IP here",
    [string]$Username = "type username here",
    [string]$Password = "type password here",
    [int]$RebootConfirmTimeoutSec = 60,
    [int]$PingIntervalSec = 1
)
```

| Parameter                 | Description                                                          |
| ------------------------- | -------------------------------------------------------------------- |
| `RemoteIP`                | IP of the far-end radio (rebooted **first**)                         |
| `LocalIP`                 | IP of the near-end radio (rebooted **second**)                       |
| `Username`                | SSH username for the radios                                          |
| `Password`                | SSH password for the radios                                          |
| `RebootConfirmTimeoutSec` | How long to wait for a device to stop responding to ping (default 60) |
| `PingIntervalSec`         | Seconds between ping checks (default 1)                              |

Alternatively, pass any of these on the command line instead of editing the file:

```powershell
.\reboot-siklu.ps1 -RemoteIP 192.0.2.2 -LocalIP 192.0.2.1 -Username myuser -Password mypassword
```

## Usage

Run manually:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\reboot-siklu.ps1"
```

### Scheduling with Task Scheduler

1. Open **Task Scheduler** → **Create Task**.
2. **General**: select *Run whether user is logged on or not*.
3. **Triggers**: add the schedule you want (e.g. weekly, at a quiet time).
4. **Actions**: *Start a program*
   - Program: `powershell.exe`
   - Arguments: `-NoProfile -ExecutionPolicy Bypass -File "C:\path\to\reboot-siklu.ps1"`
5. Save, then check `logs\reboot_log.txt` after the first run.

## Logs

All output is written to `logs\reboot_log.txt` in the script's folder. Temporary files used during the SSH session are created in the same folder and deleted when the script finishes.

## Security notes

- The password is stored in plain text in the script (or in the scheduled task's arguments). Restrict file permissions accordingly and never commit your real credentials.
- Host key checking is disabled (`StrictHostKeyChecking=no`) so the script can run unattended. Only use it on networks you trust.

## Disclaimer

Provided as-is, without warranty. Test it on your own equipment before scheduling it - you are rebooting network links, so make sure you have a way to recover if a device does not come back up.
