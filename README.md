# LINUX-Telegram-TEMP-alert
A simple temperature alert script for proxmox/linux on Telegram

# Instruction

1. Copy alertemp.sh in /root/ folder
2. Edit parameter in alertemp.sh with your telegram key and chat ID, if you need edit the temperature threshold
3. Copy tempcheck.service in /etc/systemd/system/ folder
4. Copy /tempcheck.timer in /etc/systemd/system/ folder
5. Execute systemctl enable --now tempcheck.timer
