# LINUX Telegram TEMP alert

A simple CPU temperature alerting system for **Proxmox / Linux**, with notifications over **Telegram**. The script reads the package temperature via `lm-sensors` and, when a threshold is exceeded, sends a message to a Telegram bot. A second notification is sent when the temperature drops back below the threshold.

Periodic execution is handled by a **systemd timer**, not by an internal loop: the script is invoked at regular intervals, performs a single check, and exits.

---

## Repository contents

| File | Description |
|------|-------------|
| `alertemp.sh` | Main script: reads the temperature and sends alerts |
| `tempcheck.service` | systemd unit (one-shot) that runs the script |
| `tempcheck.timer` | systemd timer that triggers the service periodically |
| `install.sh` | Automated installer (dependencies, files, units, activation) |

---

## Requirements

- `lm-sensors` (the `sensors` command)
- `curl`
- `systemd`
- A **Telegram bot** and its **chat ID** (see below)

On Debian/Ubuntu/Proxmox: `apt install lm-sensors curl`
On Fedora: `dnf install lm_sensors curl`

If `sensors` does not show the `Package id 0:` line, run `sensors-detect` first (answering YES to the defaults), or adjust the `SENSOR_LABEL` variable in the script to match your output.

---

## Creating the Telegram bot

1. In Telegram open **@BotFather**, create a bot with `/newbot` and note the **token**.
2. Start a chat with your bot (send it any message).
3. Get your **chat ID**: open
   `https://api.telegram.org/bot<TOKEN>/getUpdates`
   and read the `chat.id` field.

---

## Automated installation (recommended)

From the repository folder:

```bash
sudo ./install.sh
```

To run it as a user other than root:

```bash
sudo RUN_USER=monitor ./install.sh
```

The installer:

- checks and installs the dependencies (`sensors`, `curl`);
- copies `alertemp.sh` (to `/root/` for root, to `/usr/local/bin/` for other users);
- creates the credentials template `/etc/alertemp.env` (permissions `600`);
- installs and configures the units, aligning user and path;
- enables and starts the timer.

After installation, **edit the credentials**:

```bash
sudo nano /etc/alertemp.env
```

---

## Manual installation

```bash
# 1. Script
sudo cp alertemp.sh /root/ && sudo chmod +x /root/alertemp.sh

# 2. Credentials (kept outside the script, do NOT commit them)
sudo tee /etc/alertemp.env > /dev/null << 'ENVEOF'
TELEGRAM_BOT_TOKEN="123456:ABC..."
TELEGRAM_CHAT_ID="123456789"
ENVEOF
sudo chmod 600 /etc/alertemp.env

# 3. systemd units
sudo cp tempcheck.service tempcheck.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tempcheck.timer
```

---

## Configuration

Variables are set in `/etc/alertemp.env` (or as `Environment=` in the service):

| Variable | Default | Description |
|----------|---------|-------------|
| `TELEGRAM_BOT_TOKEN` | — | Bot token (required) |
| `TELEGRAM_CHAT_ID` | — | Destination chat ID (required) |
| `THRESHOLD` | `80` | Alert threshold in degrees C |
| `SENSOR_LABEL` | `Package id 0:` | Line of `sensors` to read |
| `ALERT_FILE` | `/tmp/alertemp_<host>_sent` | Anti-spam state file |

The check interval is set in `tempcheck.timer` (default: every 30 s):

```ini
[Timer]
OnBootSec=30
OnUnitActiveSec=30
AccuracySec=5s
```

> Note: avoid very low `AccuracySec` values (e.g. `1ms`): they prevent systemd from coalescing wakeups and keep the CPU awake continuously, which is counterproductive on a machine you are monitoring for heat. For a temperature alert, 30-60 s is more than adequate.

---

## Verification and management

```bash
systemctl start tempcheck.service        # immediate test run
journalctl -u tempcheck.service -n 20    # logs
systemctl list-timers tempcheck.timer    # next run
```

The script sends the alert only once when the threshold is exceeded (using the state file) and a recovery message when the temperature returns below the threshold.

---

## Notes

- Credentials must NOT be placed in the script or committed: keep them in `/etc/alertemp.env` with `600` permissions.
- `coretemp` sensors are generally readable by any user; if you use an unprivileged user, make sure it can write `ALERT_FILE`.

---

## License

This project is released under the **GNU General Public License v3.0
(GPL-3.0)**. You are free to use, study, modify and redistribute it under the
terms of the license, provided WITHOUT ANY WARRANTY. See the
[`LICENSE`](LICENSE) file or <https://www.gnu.org/licenses/gpl-3.0.html>.

> Consistency note: make sure the repository `LICENSE` file is GPL-3.0,
> to align it with the headers present in the sources.

## Author

[https://github.com/Leproide](https://github.com/Leproide)
