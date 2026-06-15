#!/bin/bash

#    install.sh - Installer for LINUX-Telegram-TEMP-alert
#    Author: https://github.com/Leproide
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -euo pipefail

# -------------------------------------------------------------------------------
# Parameters (override from environment: e.g. RUN_USER=monitor ./install.sh)
# -------------------------------------------------------------------------------
RUN_USER="${RUN_USER:-root}"                 # user that will run the service
SCRIPT_SRC="${SCRIPT_SRC:-./alertemp.sh}"    # script source
SERVICE_SRC="${SERVICE_SRC:-./tempcheck.service}"
TIMER_SRC="${TIMER_SRC:-./tempcheck.timer}"
ENV_FILE="${ENV_FILE:-/etc/alertemp.env}"    # credentials file
SYSTEMD_DIR="/etc/systemd/system"

# Install dir of the script: /root for root, otherwise /usr/local/bin
if [ "$RUN_USER" = "root" ]; then
    SCRIPT_DEST="${SCRIPT_DEST:-/root/alertemp.sh}"
else
    SCRIPT_DEST="${SCRIPT_DEST:-/usr/local/bin/alertemp.sh}"
fi

# -------------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------------
info() { echo -e "\e[1;34m[*]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
die()  { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

# -------------------------------------------------------------------------------
# Preliminary checks
# -------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Run the installer as root (sudo ./install.sh)"

# systemd present?
command -v systemctl >/dev/null 2>&1 || die "systemd not found: this installer requires systemd"

# Source files present?
for f in "$SCRIPT_SRC" "$SERVICE_SRC" "$TIMER_SRC"; do
    [ -f "$f" ] || die "Missing source file: $f (run the installer from the repo folder)"
done

# Does the chosen user exist?
if ! id "$RUN_USER" >/dev/null 2>&1; then
    die "User '$RUN_USER' does not exist. Create it first, or use RUN_USER=root"
fi

# Runtime dependencies: lm-sensors and curl
info "Checking dependencies (sensors, curl)..."
MISSING=()
command -v sensors >/dev/null 2>&1 || MISSING+=("lm-sensors")
command -v curl    >/dev/null 2>&1 || MISSING+=("curl")

if [ "${#MISSING[@]}" -gt 0 ]; then
    warn "Missing: ${MISSING[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        info "Installing with apt-get..."
        apt-get update -qq && apt-get install -y "${MISSING[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        info "Installing with dnf..."
        # on Fedora the package is lm_sensors
        dnf install -y "${MISSING[@]/lm-sensors/lm_sensors}"
    else
        die "Unrecognized package manager: install manually ${MISSING[*]}"
    fi
else
    ok "Dependencies already present."
fi

# Does 'sensors' return anything?
if ! sensors 2>/dev/null | grep -q "Package id 0:"; then
    warn "'sensors' does not show 'Package id 0:'. You may need to run: sensors-detect"
    warn "Or adjust SENSOR_LABEL in the script to match your output."
fi

# -------------------------------------------------------------------------------
# Script installation
# -------------------------------------------------------------------------------
info "Installing the script to $SCRIPT_DEST ..."
install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DEST"
ok "Script installed."

# -------------------------------------------------------------------------------
# Credentials file
# -------------------------------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
    ok "Credentials file already present: $ENV_FILE (leaving it untouched)."
else
    info "Creating credentials template at $ENV_FILE ..."
    cat > "$ENV_FILE" << 'ENVEOF'
# Telegram credentials for alertemp.sh
# Replace with your real values, then do NOT commit this file anywhere.
TELEGRAM_BOT_TOKEN="PUT_YOUR_TOKEN_HERE"
TELEGRAM_CHAT_ID="PUT_YOUR_CHAT_ID_HERE"
# Optional: alert threshold in degrees C (default 80)
#THRESHOLD="80"
ENVEOF
    chmod 600 "$ENV_FILE"
    chown "$RUN_USER":"$RUN_USER" "$ENV_FILE" 2>/dev/null || true
    warn "Remember to edit $ENV_FILE with your real token and chat ID."
fi

# -------------------------------------------------------------------------------
# Unit files: copy and set the chosen user/path
# -------------------------------------------------------------------------------
info "Installing unit files to $SYSTEMD_DIR ..."
install -m 0644 "$SERVICE_SRC" "$SYSTEMD_DIR/tempcheck.service"
install -m 0644 "$TIMER_SRC"   "$SYSTEMD_DIR/tempcheck.timer"

# Align User= and ExecStart= to the chosen value (in-place sed on installed file)
sed -i -E "s|^User=.*|User=${RUN_USER}|"              "$SYSTEMD_DIR/tempcheck.service"
sed -i -E "s|^ExecStart=.*|ExecStart=${SCRIPT_DEST}|" "$SYSTEMD_DIR/tempcheck.service"
ok "Units configured for user '$RUN_USER' and script '$SCRIPT_DEST'."

# -------------------------------------------------------------------------------
# Activation
# -------------------------------------------------------------------------------
info "Reloading systemd and enabling the timer..."
systemctl daemon-reload
systemctl enable --now tempcheck.timer
ok "Timer active."

echo
ok "Installation complete."
echo "  - Script:        $SCRIPT_DEST"
echo "  - Credentials:   $ENV_FILE  (edit it if you haven't already)"
echo "  - User:          $RUN_USER"
echo
echo "Useful commands:"
echo "  systemctl start tempcheck.service     # immediate test"
echo "  journalctl -u tempcheck.service -n 20 # logs"
echo "  systemctl list-timers tempcheck.timer # next run"
