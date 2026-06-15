#!/bin/bash

#    alertemp.sh - CPU temperature alert via Telegram (for proxmox/linux)
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

# -------------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------------
# Credentials are kept OUTSIDE the script so they don't end up on git.
# Create /etc/alertemp.env (or ~/.config/alertemp.env) with:
#   TELEGRAM_BOT_TOKEN="123456:ABC..."
#   TELEGRAM_CHAT_ID="123456789"
# and protect it:  chmod 600 /etc/alertemp.env
CONFIG_FILE="${ALERTEMP_CONFIG:-/etc/alertemp.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Can also be overridden via environment variables (see unit file)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

THRESHOLD="${THRESHOLD:-80}"                      # alert threshold in degrees C
SENSOR_LABEL="${SENSOR_LABEL:-Package id 0:}"     # 'sensors' line to read
# State file (anti-spam). Made unique per host so different VMs/nodes don't
# clobber the same file if they share /tmp.
ALERT_FILE="${ALERT_FILE:-/tmp/alertemp_$(hostname)_sent}"

API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# -------------------------------------------------------------------------------
# Functions
# -------------------------------------------------------------------------------

# Send a Telegram message (url-encoded text, no markdown: more robust against
# hostnames/text containing special characters).
send_telegram() {
    local message="$1"
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "alertemp: missing Telegram credentials ($CONFIG_FILE)" >&2
        return 1
    fi
    curl -s -o /dev/null --max-time 10 \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "disable_web_page_preview=1" \
        "$API_URL"
}

# Read the package temperature from 'sensors'. Prints an integer in degrees C,
# or nothing if unavailable. Handles negative values too.
read_temp() {
    sensors 2>/dev/null \
        | grep -m1 -F "$SENSOR_LABEL" \
        | grep -oE '[+-][0-9]+\.[0-9]+' \
        | head -n1 \
        | cut -d. -f1 \
        | tr -d '+'
}

# -------------------------------------------------------------------------------
# Main (one-shot: the systemd timer invokes it periodically)
# -------------------------------------------------------------------------------
temp="$(read_temp)"

# Guard: without a valid integer do nothing (avoids arithmetic errors when
# 'sensors' does not respond or its output changes).
if ! [[ "$temp" =~ ^-?[0-9]+$ ]]; then
    echo "alertemp: temperature not readable (label '$SENSOR_LABEL')" >&2
    exit 1
fi

if (( temp > THRESHOLD )); then
    # Above threshold: send the alert only once
    if [ ! -f "$ALERT_FILE" ]; then
        if send_telegram "TEMP ALERT on $(hostname): ${temp} degrees C (threshold ${THRESHOLD})"; then
            touch "$ALERT_FILE"
        fi
    fi
else
    # Below threshold: send a recovery notice only if an alert was active
    if [ -f "$ALERT_FILE" ]; then
        if send_telegram "Temperature back to normal on $(hostname): ${temp} degrees C"; then
            rm -f "$ALERT_FILE"
        fi
    fi
fi
