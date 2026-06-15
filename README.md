# LINUX Telegram TEMP alert

Un semplice sistema di alert sulla temperatura della CPU per **Proxmox / Linux**, con notifiche su **Telegram**. Lo script legge la temperatura del package tramite `lm-sensors` e, al superamento di una soglia, invia un messaggio a un bot Telegram. Una seconda notifica avvisa quando la temperatura rientra sotto la soglia.

L'esecuzione periodica e' gestita da un **timer systemd**, non da un loop interno: lo script viene richiamato a intervalli regolari, fa un singolo controllo e termina.

---

## Contenuto del repository

| File | Descrizione |
|------|-------------|
| `alertemp.sh` | Script principale: legge la temperatura e invia gli alert |
| `tempcheck.service` | Unit systemd (one-shot) che esegue lo script |
| `tempcheck.timer` | Timer systemd che richiama il service periodicamente |
| `install.sh` | Installer automatico (dipendenze, file, unit, attivazione) |

---

## Requisiti

- `lm-sensors` (comando `sensors`)
- `curl`
- `systemd`
- Un **bot Telegram** e il relativo **chat ID** (vedi sotto)

Su Debian/Ubuntu/Proxmox: `apt install lm-sensors curl`
Su Fedora: `dnf install lm_sensors curl`

Se `sensors` non mostra la riga `Package id 0:`, esegui prima `sensors-detect` (rispondendo YES ai default) oppure adatta la variabile `SENSOR_LABEL` nello script al tuo output.

---

## Creare il bot Telegram

1. Su Telegram apri **@BotFather**, crea un bot con `/newbot` e annota il **token**.
2. Avvia una chat col tuo bot (mandagli un messaggio qualsiasi).
3. Ricava il tuo **chat ID**: apri
   `https://api.telegram.org/bot<TOKEN>/getUpdates`
   e leggi il campo `chat.id`.

---

## Installazione automatica (consigliata)

Dalla cartella del repository:

```bash
sudo ./install.sh
```

Per farlo eseguire da un utente diverso da root:

```bash
sudo RUN_USER=monitor ./install.sh
```

L'installer:

- verifica e installa le dipendenze (`sensors`, `curl`);
- copia `alertemp.sh` (in `/root/` per root, in `/usr/local/bin/` per altri utenti);
- crea il template credenziali `/etc/alertemp.env` (permessi `600`);
- installa e configura gli unit allineando utente e percorso;
- abilita e avvia il timer.

Dopo l'installazione, **edita le credenziali**:

```bash
sudo nano /etc/alertemp.env
```

---

## Installazione manuale

```bash
# 1. Script
sudo cp alertemp.sh /root/ && sudo chmod +x /root/alertemp.sh

# 2. Credenziali (fuori dallo script, NON committarle)
sudo tee /etc/alertemp.env > /dev/null << 'ENVEOF'
TELEGRAM_BOT_TOKEN="123456:ABC..."
TELEGRAM_CHAT_ID="123456789"
ENVEOF
sudo chmod 600 /etc/alertemp.env

# 3. Unit systemd
sudo cp tempcheck.service tempcheck.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tempcheck.timer
```

---

## Configurazione

Le variabili si impostano in `/etc/alertemp.env` (o come `Environment=` nel service):

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| `TELEGRAM_BOT_TOKEN` | — | Token del bot (obbligatorio) |
| `TELEGRAM_CHAT_ID` | — | Chat ID di destinazione (obbligatorio) |
| `THRESHOLD` | `80` | Soglia di allarme in gradi C |
| `SENSOR_LABEL` | `Package id 0:` | Riga di `sensors` da leggere |
| `ALERT_FILE` | `/tmp/alertemp_<host>_sent` | File di stato anti-spam |

L'intervallo di controllo si regola nel `tempcheck.timer` (default: ogni 30 s):

```ini
[Timer]
OnBootSec=30
OnUnitActiveSec=30
AccuracySec=5s
```

> Nota: evita `AccuracySec` molto bassi (es. `1ms`): impediscono a systemd di accorpare i wakeup e tengono la CPU sveglia di continuo, controproducente su una macchina che stai monitorando per il calore. Per un alert di temperatura, 30-60 s sono piu' che adeguati.

---

## Verifica e gestione

```bash
systemctl start tempcheck.service        # esecuzione di test immediata
journalctl -u tempcheck.service -n 20    # log
systemctl list-timers tempcheck.timer    # prossima esecuzione
```

Lo script invia l'alert una sola volta al superamento della soglia (tramite il file di stato) e un messaggio di rientro quando la temperatura ritorna sotto soglia.

---

## Note

- Le credenziali NON vanno inserite nello script ne' committate: tienile in `/etc/alertemp.env` con permessi `600`.
- I sensori `coretemp` sono in genere leggibili da qualsiasi utente; se usi un utente non privilegiato, assicurati che possa scrivere `ALERT_FILE`.

---

## License

Questo progetto e' rilasciato sotto licenza **GNU General Public License v3.0
(GPL-3.0)**. Sei libero di usarlo, studiarlo, modificarlo e ridistribuirlo nei
termini della licenza, fornito SENZA ALCUNA GARANZIA. Vedi il file
[`LICENSE`](LICENSE) o <https://www.gnu.org/licenses/gpl-3.0.html>.

> Nota di coerenza: assicurati che il file `LICENSE` del repository sia GPL-3.0,
> per allinearlo agli header presenti nei sorgenti.

## Author

[https://github.com/Leproide](https://github.com/Leproide)
