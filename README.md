# LINUX Telegram TEMP alert
A simple temperature alert script for proxmox/linux on Telegram

# Instruction


1. Install sensors (apt install lm-sensors on Debian/Ubuntu etc)
2. Copy alertemp.sh in /root/ folder
3. Edit parameter in alertemp.sh with your telegram key and chat ID, if you need edit the temperature threshold
4. Copy tempcheck.service in /etc/systemd/system/ folder
5. Copy /tempcheck.timer in /etc/systemd/system/ folder
6. Execute systemctl enable --now tempcheck.timer

Check that the script can write to temp.
if it cannot, it won't be able to create the temporary file.
