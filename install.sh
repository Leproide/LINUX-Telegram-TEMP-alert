#!/bin/bash

#    install.sh - Installer per LINUX-Telegram-TEMP-alert
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
# Parametri (override da ambiente: es. RUN_USER=monitor ./install.sh)
# -------------------------------------------------------------------------------
RUN_USER="${RUN_USER:-root}"                 # utente che eseguira' il servizio
SCRIPT_SRC="${SCRIPT_SRC:-./alertemp.sh}"    # sorgente dello script
SERVICE_SRC="${SERVICE_SRC:-./tempcheck.service}"
TIMER_SRC="${TIMER_SRC:-./tempcheck.timer}"
ENV_FILE="${ENV_FILE:-/etc/alertemp.env}"    # file credenziali
SYSTEMD_DIR="/etc/systemd/system"

# Dir di installazione dello script: /root per root, altrimenti /usr/local/bin
if [ "$RUN_USER" = "root" ]; then
    SCRIPT_DEST="${SCRIPT_DEST:-/root/alertemp.sh}"
else
    SCRIPT_DEST="${SCRIPT_DEST:-/usr/local/bin/alertemp.sh}"
fi

# -------------------------------------------------------------------------------
# Helper
# -------------------------------------------------------------------------------
info() { echo -e "\e[1;34m[*]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
die()  { echo -e "\e[1;31m[x]\e[0m $*" >&2; exit 1; }

# -------------------------------------------------------------------------------
# Controlli preliminari
# -------------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Esegui l'installer come root (sudo ./install.sh)"

# systemd presente?
command -v systemctl >/dev/null 2>&1 || die "systemd non trovato: questo installer richiede systemd"

# File sorgente presenti?
for f in "$SCRIPT_SRC" "$SERVICE_SRC" "$TIMER_SRC"; do
    [ -f "$f" ] || die "File sorgente mancante: $f (lancia l'installer dalla cartella del repo)"
done

# L'utente scelto esiste?
if ! id "$RUN_USER" >/dev/null 2>&1; then
    die "L'utente '$RUN_USER' non esiste. Crealo prima, oppure usa RUN_USER=root"
fi

# Dipendenze runtime: lm-sensors e curl
info "Verifico le dipendenze (sensors, curl)..."
MISSING=()
command -v sensors >/dev/null 2>&1 || MISSING+=("lm-sensors")
command -v curl    >/dev/null 2>&1 || MISSING+=("curl")

if [ "${#MISSING[@]}" -gt 0 ]; then
    warn "Mancano: ${MISSING[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        info "Installo con apt-get..."
        apt-get update -qq && apt-get install -y "${MISSING[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        info "Installo con dnf..."
        # su Fedora il pacchetto e' lm_sensors
        dnf install -y "${MISSING[@]/lm-sensors/lm_sensors}"
    else
        die "Gestore pacchetti non riconosciuto: installa manualmente ${MISSING[*]}"
    fi
else
    ok "Dipendenze gia' presenti."
fi

# 'sensors' restituisce qualcosa?
if ! sensors 2>/dev/null | grep -q "Package id 0:"; then
    warn "'sensors' non mostra 'Package id 0:'. Potresti dover lanciare: sensors-detect"
    warn "Oppure adatta SENSOR_LABEL nello script al tuo output."
fi

# -------------------------------------------------------------------------------
# Installazione script
# -------------------------------------------------------------------------------
info "Installo lo script in $SCRIPT_DEST ..."
install -m 0755 "$SCRIPT_SRC" "$SCRIPT_DEST"
ok "Script installato."

# -------------------------------------------------------------------------------
# File credenziali
# -------------------------------------------------------------------------------
if [ -f "$ENV_FILE" ]; then
    ok "File credenziali gia' presente: $ENV_FILE (non lo tocco)."
else
    info "Creo il template credenziali in $ENV_FILE ..."
    cat > "$ENV_FILE" << 'ENVEOF'
# Credenziali Telegram per alertemp.sh
# Sostituisci con i tuoi valori reali, poi NON committarlo da nessuna parte.
TELEGRAM_BOT_TOKEN="INSERISCI_IL_TOKEN"
TELEGRAM_CHAT_ID="INSERISCI_IL_CHAT_ID"
# Opzionale: soglia di allarme in gradi C (default 80)
#THRESHOLD="80"
ENVEOF
    chmod 600 "$ENV_FILE"
    chown "$RUN_USER":"$RUN_USER" "$ENV_FILE" 2>/dev/null || true
    warn "Ricorda di editare $ENV_FILE con token e chat ID reali."
fi

# -------------------------------------------------------------------------------
# Unit file: copio e imposto l'utente/percorso scelti
# -------------------------------------------------------------------------------
info "Installo gli unit file in $SYSTEMD_DIR ..."
install -m 0644 "$SERVICE_SRC" "$SYSTEMD_DIR/tempcheck.service"
install -m 0644 "$TIMER_SRC"   "$SYSTEMD_DIR/tempcheck.timer"

# Allineo User= e ExecStart= al valore scelto (sed in-place sul file installato)
sed -i -E "s|^User=.*|User=${RUN_USER}|"            "$SYSTEMD_DIR/tempcheck.service"
sed -i -E "s|^ExecStart=.*|ExecStart=${SCRIPT_DEST}|" "$SYSTEMD_DIR/tempcheck.service"
ok "Unit configurati per utente '$RUN_USER' e script '$SCRIPT_DEST'."

# -------------------------------------------------------------------------------
# Attivazione
# -------------------------------------------------------------------------------
info "Ricarico systemd e abilito il timer..."
systemctl daemon-reload
systemctl enable --now tempcheck.timer
ok "Timer attivo."

echo
ok "Installazione completata."
echo "  - Script:       $SCRIPT_DEST"
echo "  - Credenziali:  $ENV_FILE  (editalo se non l'hai gia' fatto)"
echo "  - Utente:       $RUN_USER"
echo
echo "Comandi utili:"
echo "  systemctl start tempcheck.service     # test immediato"
echo "  journalctl -u tempcheck.service -n 20 # log"
echo "  systemctl list-timers tempcheck.timer # prossima esecuzione"
