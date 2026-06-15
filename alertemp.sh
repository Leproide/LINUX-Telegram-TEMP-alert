#!/bin/bash

#    alertemp.sh - Alert temperatura CPU via Telegram (per proxmox/linux)
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
# Configurazione
# -------------------------------------------------------------------------------
# Le credenziali stanno FUORI dallo script cosi' non finiscono su git.
# Crea /etc/alertemp.env (o ~/.config/alertemp.env) con:
#   TELEGRAM_BOT_TOKEN="123456:ABC..."
#   TELEGRAM_CHAT_ID="123456789"
# e proteggilo:  chmod 600 /etc/alertemp.env
CONFIG_FILE="${ALERTEMP_CONFIG:-/etc/alertemp.env}"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

# Override possibili anche da variabili d'ambiente (vedi unit file)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

THRESHOLD="${THRESHOLD:-80}"                      # soglia di allarme in gradi C
SENSOR_LABEL="${SENSOR_LABEL:-Package id 0:}"     # riga di 'sensors' da leggere
# File di stato (anti-spam). Reso univoco per host cosi' VM/nodi diversi non
# si pestano lo stesso file se montano /tmp condivisa.
ALERT_FILE="${ALERT_FILE:-/tmp/alertemp_$(hostname)_sent}"

API_URL="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

# -------------------------------------------------------------------------------
# Funzioni
# -------------------------------------------------------------------------------

# Invia un messaggio Telegram (testo url-encoded, niente markdown: piu' robusto
# su hostname/testi con caratteri speciali).
send_telegram() {
    local message="$1"
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "alertemp: credenziali Telegram mancanti ($CONFIG_FILE)" >&2
        return 1
    fi
    curl -s -o /dev/null --max-time 10 \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "disable_web_page_preview=1" \
        "$API_URL"
}

# Legge la temperatura del package da 'sensors'. Stampa un intero in gradi C,
# oppure niente se non disponibile. Gestisce anche valori negativi.
read_temp() {
    sensors 2>/dev/null \
        | grep -m1 -F "$SENSOR_LABEL" \
        | grep -oE '[+-][0-9]+\.[0-9]+' \
        | head -n1 \
        | cut -d. -f1 \
        | tr -d '+'
}

# -------------------------------------------------------------------------------
# Main (one-shot: e' il timer systemd a richiamarlo periodicamente)
# -------------------------------------------------------------------------------
temp="$(read_temp)"

# Guardia: senza un intero valido non faccio nulla (evita errori aritmetici
# quando 'sensors' non risponde o cambia output).
if ! [[ "$temp" =~ ^-?[0-9]+$ ]]; then
    echo "alertemp: temperatura non leggibile (label '$SENSOR_LABEL')" >&2
    exit 1
fi

if (( temp > THRESHOLD )); then
    # Sopra soglia: invio l'allarme una sola volta
    if [ ! -f "$ALERT_FILE" ]; then
        if send_telegram "TEMP ALERT su $(hostname): ${temp} gradi C (soglia ${THRESHOLD})"; then
            touch "$ALERT_FILE"
        fi
    fi
else
    # Sotto soglia: notifica di rientro solo se c'era un allarme attivo
    if [ -f "$ALERT_FILE" ]; then
        if send_telegram "Temperatura rientrata su $(hostname): ${temp} gradi C"; then
            rm -f "$ALERT_FILE"
        fi
    fi
fi
