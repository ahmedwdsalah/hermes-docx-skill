# Cron / Scheduler Setup — Platform-Specific Reference

This document provides exact commands and troubleshooting steps for each platform's
scheduler. The `scripts/install.sh` script handles setup automatically; use this
reference when the agent needs to debug or manually configure the scheduler.

---

## macOS — launchd

### Install (automated by install.sh)
```bash
# Plist is written to:
~/Library/LaunchAgents/com.docintel.scan.plist

# Load it:
launchctl load ~/Library/LaunchAgents/com.docintel.scan.plist
```

### Verify
```bash
# Check it's loaded:
launchctl list | grep docintel

# Check next run time:
launchctl print gui/$(id -u)/com.docintel.scan 2>/dev/null | grep -i "next"

# View logs:
cat ~/DocIntel/logs/cron_stdout.log
cat ~/DocIntel/logs/cron_stderr.log
```

### Manual run
```bash
launchctl start com.docintel.scan
```

### Uninstall
```bash
launchctl unload ~/Library/LaunchAgents/com.docintel.scan.plist
rm ~/Library/LaunchAgents/com.docintel.scan.plist
```

### Troubleshooting
- **"Operation not permitted"**: macOS may block Terminal from accessing
  Documents/Desktop/Downloads. Go to System Settings > Privacy & Security >
  Files and Folders > grant Terminal access.
- **Job not running**: Check `launchctl list` for non-zero exit code.
  Run the pipeline manually first to verify it works:
  `python3 ~/DocIntel/scripts/pipeline.py scan`
- **Plist syntax error**: Validate with `plutil -lint ~/Library/LaunchAgents/com.docintel.scan.plist`

---

## Linux — crontab

### Install (automated by install.sh)
```bash
# Entry added to crontab:
0 6 * * * cd ~/DocIntel && python3 scripts/pipeline.py scan >> ~/DocIntel/logs/cron_stdout.log 2>> ~/DocIntel/logs/cron_stderr.log
```

### Verify
```bash
# List all cron jobs:
crontab -l

# Check cron service is running:
systemctl status cron        # Debian/Ubuntu
systemctl status crond       # RHEL/Fedora
```

### Manual run
```bash
cd ~/DocIntel && python3 scripts/pipeline.py scan
```

### Uninstall
```bash
crontab -l | grep -v "pipeline.py scan" | crontab -
```

### Troubleshooting
- **Cron not running**: Ensure the cron daemon is active:
  `sudo systemctl enable --now cron` (Debian) or `sudo systemctl enable --now crond` (RHEL)
- **Python not found in cron**: Cron runs with a minimal PATH. Use absolute paths:
  `0 6 * * * cd /home/user/DocIntel && /usr/bin/python3 scripts/pipeline.py scan`
- **Log file not written**: Ensure `~/DocIntel/logs/` exists and is writable.
- **Permissions**: Cron runs as the user who owns the crontab. Ensure that user
  has read access to the scanned directories.

---

## Windows — Task Scheduler (schtasks)

### Install (automated by install.sh)
```cmd
schtasks /create /tn "DocIntelScan" /tr "python C:\DocIntel\scripts\pipeline.py scan" /sc daily /st 06:00 /f
```

If schtasks fails (needs admin), the install script prints the command to run manually.

### Verify
```cmd
schtasks /query /tn DocIntelScan /v
```

### Manual run
```cmd
schtasks /run /tn DocIntelScan
```
Or directly:
```cmd
python C:\DocIntel\scripts\pipeline.py scan
```

### Uninstall
```cmd
schtasks /delete /tn DocIntelScan /f
```

### Troubleshooting
- **"Access denied"**: schtasks may require an elevated (admin) terminal.
  Right-click Terminal > "Run as administrator".
- **Python not found**: Use the full path to python.exe:
  `C:\Users\Ahmed\AppData\Local\Programs\Python\Python311\python.exe`
- **Task runs but does nothing**: The task runs in the SYSTEM account context
  by default. Add `/ru <username> /rp <password>` to run as a specific user.
- **Paths with spaces**: Always quote paths: `"C:\DocIntel\scripts\pipeline.py"`
- **WSL / Git Bash**: If using Git Bash, the path needs forward slashes:
  `C:/DocIntel/scripts/pipeline.py`

---

## WSL (Windows Subsystem for Linux)

If running inside WSL (not bare Windows):

- Root: `~/DocIntel` (Linux-style path)
- Windows drives accessible at `/mnt/c/`
- Scan directories must use Linux paths or `/mnt/c/Users/...`
- Crontab works normally inside WSL
- **Pitfall**: WSL shuts down when idle. Ensure WSL stays running or use
  Windows Task Scheduler to trigger WSL commands.

---

## Verifying the Cron Job Works

On any platform, the definitive test:
1. Place a test .docx file in the scanned directory (e.g., `~/Downloads/test.docx`)
2. Wait for the next 06:00 run, OR trigger manually
3. Check `~/DocIntel/collected/manifest.jsonl` for the new entry
4. Check `~/DocIntel/logs/cron_stdout.log` for scan output
