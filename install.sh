#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Debian 13 + KeyHelp + SOGo Installer
#
# DISCLAIMER / HAFTUNGSAUSSCHLUSS:
# Use at your own risk / Nutzung auf eigene Gefahr.
# Always create a complete backup or snapshot first.
# Immer zuerst ein vollstaendiges Backup oder einen Snapshot erstellen.
#
# This project is not affiliated with KeyHelp, Keyweb or SOGo.
# Dieses Projekt steht in keiner offiziellen Verbindung zu KeyHelp, Keyweb
# oder SOGo.
#
# The script was created with the help of ChatGPT and practically tested by
# the repository owner on a Debian 13 + KeyHelp test installation.
# Das Script wurde mit Hilfe von ChatGPT erstellt und vom Repository-Inhaber
# auf einer Debian-13-/KeyHelp-Testinstallation praktisch getestet.
###############################################################################

readonly SCRIPT_VERSION="0.2.0"
readonly SOGO_DB="sogo"
readonly SOGO_DB_USER="sogo"
readonly CREDENTIAL_FILE="/root/.sogo-db-credentials"

LANGUAGE="en"

msg() {
    local key="$1"
    case "${LANGUAGE}:${key}" in
        de:root) echo "Bitte diesen Installer als root ausfuehren." ;;
        en:root) echo "Please run this installer as root." ;;

        de:os) echo "Dieser Installer unterstuetzt aktuell nur Debian 13." ;;
        en:os) echo "This installer currently supports Debian 13 only." ;;

        de:keyhelp_missing) echo "Die KeyHelp-Datenbank wurde nicht gefunden. Ist KeyHelp vollstaendig installiert?" ;;
        en:keyhelp_missing) echo "KeyHelp database not found. Is KeyHelp fully installed?" ;;

        de:table_missing) echo "Die KeyHelp-Tabelle 'keyhelp.mail_users' wurde nicht gefunden." ;;
        en:table_missing) echo "KeyHelp table 'keyhelp.mail_users' not found." ;;

        de:fqdn_missing) echo "Kein gueltiger Server-FQDN erkannt. Bitte zuerst den KeyHelp-Serverhostname konfigurieren." ;;
        en:fqdn_missing) echo "No valid server FQDN detected. Configure the KeyHelp server hostname first." ;;

        de:profile) echo "Installationsprofil:" ;;
        en:profile) echo "Installation profile:" ;;

        de:minimal) echo "Webmail + Kalender + Kontakte" ;;
        en:minimal) echo "Webmail + calendar + contacts" ;;

        de:standard) echo "Minimal + Sieve-Filter + Abwesenheit + Weiterleitungen" ;;
        en:standard) echo "Minimal + Sieve filters + vacation + forwarding" ;;

        de:full) echo "Standard + Exchange ActiveSync" ;;
        en:full) echo "Standard + Exchange ActiveSync" ;;

        de:custom) echo "Optionale Funktionen einzeln auswaehlen" ;;
        en:custom) echo "Choose optional features individually" ;;

        de:selection) echo "Auswahl [1-4, Standard: 3]: " ;;
        en:selection) echo "Selection [1-4, default: 3]: " ;;

        de:sieve_q) echo "Sieve-Filter aktivieren?" ;;
        en:sieve_q) echo "Enable Sieve filters?" ;;

        de:vacation_q) echo "Abwesenheitsnotizen aktivieren?" ;;
        en:vacation_q) echo "Enable vacation messages?" ;;

        de:forward_q) echo "Weiterleitungen in SOGo aktivieren?" ;;
        en:forward_q) echo "Enable forwarding in SOGo?" ;;

        de:activesync_q) echo "ActiveSync installieren und bereitstellen?" ;;
        en:activesync_q) echo "Install and expose ActiveSync?" ;;

        de:start_q) echo "Installation starten?" ;;
        en:start_q) echo "Start installation?" ;;

        de:cancelled) echo "Abgebrochen." ;;
        en:cancelled) echo "Cancelled." ;;

        de:invalid) echo "Ungueltige Auswahl." ;;
        en:invalid) echo "Invalid selection." ;;

        de:finished) echo "Installation abgeschlossen" ;;
        en:finished) echo "Installation finished" ;;

        *) echo "$key" ;;
    esac
}

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

trap 'printf "\n[ERROR] Installation failed at line %s.\n" "$LINENO" >&2' ERR

if [[ ${EUID} -ne 0 ]]; then
    LANGUAGE="en"
    die "$(msg root)"
fi

printf '\n============================================================\n'
printf ' Debian 13 + KeyHelp + SOGo Installer v%s\n' "$SCRIPT_VERSION"
printf '============================================================\n\n'
printf ' Language / Sprache:\n'
printf '   [1] Deutsch\n'
printf '   [2] English\n\n'
read -r -p "Selection / Auswahl [1-2, default/Standard: 1]: " LANG_SELECT
case "${LANG_SELECT:-1}" in
    1) LANGUAGE="de" ;;
    2) LANGUAGE="en" ;;
    *) LANGUAGE="de" ;;
esac

echo
if [[ "$LANGUAGE" == "de" ]]; then
    echo "WARNUNG: Nutzung auf eigene Gefahr. Vorher Backup/Snapshot erstellen."
    echo "Dieses Script wurde mit Hilfe von ChatGPT erstellt und vom Repository-Inhaber"
    echo "auf einer Debian-13-/KeyHelp-Testinstallation praktisch getestet."
else
    echo "WARNING: Use at your own risk. Create a backup/snapshot first."
    echo "This script was created with the help of ChatGPT and practically tested by"
    echo "the repository owner on a Debian 13 + KeyHelp test installation."
fi

echo

###############################################################################
# Pre-flight checks
###############################################################################

[[ -r /etc/os-release ]] || die "/etc/os-release not found."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] || die "$(msg os)"

for cmd in mariadb apache2ctl postconf doveconf systemctl hostname curl openssl; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found."
done

mariadb -Nse "SHOW DATABASES" | grep -qx keyhelp || die "$(msg keyhelp_missing)"
mariadb keyhelp -Nse "SHOW TABLES" | grep -qx mail_users || die "$(msg table_missing)"

for column in email_utf8 password login_enabled; do
    mariadb keyhelp -Nse "SHOW COLUMNS FROM mail_users LIKE '${column}'" | grep -q . || \
        die "Required KeyHelp column 'mail_users.${column}' not found. KeyHelp schema may have changed."
done

SERVER_FQDN="$(hostname -f 2>/dev/null || true)"
[[ "$SERVER_FQDN" == *.* ]] || die "$(msg fqdn_missing)"

if [[ "$LANGUAGE" == "de" ]]; then
    echo "Erkannter FQDN: ${SERVER_FQDN}"
else
    echo "Detected FQDN: ${SERVER_FQDN}"
fi

###############################################################################
# Profile selection
###############################################################################

echo
echo "$(msg profile)"
echo "  [1] Minimal"
echo "      $(msg minimal)"
echo
echo "  [2] Standard"
echo "      $(msg standard)"
echo
echo "  [3] Full"
echo "      $(msg full)"
echo
echo "  [4] Custom / Benutzerdefiniert"
echo "      $(msg custom)"
echo

read -r -p "$(msg selection)" PROFILE
PROFILE="${PROFILE:-3}"

ENABLE_SIEVE="no"
ENABLE_VACATION="no"
ENABLE_FORWARD="no"
ENABLE_ACTIVESYNC="no"

ask_yes_no() {
    local prompt="$1"
    local answer
    if [[ "$LANGUAGE" == "de" ]]; then
        read -r -p "${prompt} [J/n]: " answer
        [[ "${answer:-J}" =~ ^[JjYy]$ ]]
    else
        read -r -p "${prompt} [Y/n]: " answer
        [[ "${answer:-Y}" =~ ^[YyJj]$ ]]
    fi
}

case "$PROFILE" in
    1) ;;
    2)
        ENABLE_SIEVE="yes"
        ENABLE_VACATION="yes"
        ENABLE_FORWARD="yes"
        ;;
    3)
        ENABLE_SIEVE="yes"
        ENABLE_VACATION="yes"
        ENABLE_FORWARD="yes"
        ENABLE_ACTIVESYNC="yes"
        ;;
    4)
        ask_yes_no "$(msg sieve_q)" && ENABLE_SIEVE="yes"
        ask_yes_no "$(msg vacation_q)" && ENABLE_VACATION="yes"
        ask_yes_no "$(msg forward_q)" && ENABLE_FORWARD="yes"
        ask_yes_no "$(msg activesync_q)" && ENABLE_ACTIVESYNC="yes"
        ;;
    *) die "$(msg invalid)" ;;
esac

echo
if [[ "$LANGUAGE" == "de" ]]; then
    echo "Ausgewaehlte Funktionen:"
else
    echo "Selected features:"
fi
printf '  Sieve:      %s\n' "$ENABLE_SIEVE"
printf '  Vacation:   %s\n' "$ENABLE_VACATION"
printf '  Forwarding: %s\n' "$ENABLE_FORWARD"
printf '  ActiveSync: %s\n' "$ENABLE_ACTIVESYNC"
echo

if ! ask_yes_no "$(msg start_q)"; then
    echo "$(msg cancelled)"
    exit 0
fi

###############################################################################
# Backups and credentials
###############################################################################

BACKUP_DIR="/root/sogo-install-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

if [[ "$LANGUAGE" == "de" ]]; then
    log "Backup-Verzeichnis: ${BACKUP_DIR}"
else
    log "Backup directory: ${BACKUP_DIR}"
fi

if [[ -f "$CREDENTIAL_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CREDENTIAL_FILE"
fi

if [[ -z "${SOGO_DB_PASSWORD:-}" ]]; then
    SOGO_DB_PASSWORD="$(openssl rand -hex 24)"
fi

cat > "$CREDENTIAL_FILE" <<EOF
SOGO_DB=${SOGO_DB}
SOGO_DB_USER=${SOGO_DB_USER}
SOGO_DB_PASSWORD=${SOGO_DB_PASSWORD}
EOF
chmod 600 "$CREDENTIAL_FILE"

###############################################################################
# Database and live KeyHelp user view
###############################################################################

if [[ "$LANGUAGE" == "de" ]]; then
    log "SOGo-Datenbank und Live-KeyHelp-Benutzeransicht vorbereiten"
else
    log "Preparing SOGo database and live KeyHelp user view"
fi

mariadb <<SQL
CREATE DATABASE IF NOT EXISTS \`${SOGO_DB}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${SOGO_DB_USER}'@'localhost'
  IDENTIFIED BY '${SOGO_DB_PASSWORD}';

ALTER USER '${SOGO_DB_USER}'@'localhost'
  IDENTIFIED BY '${SOGO_DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${SOGO_DB}\`.* TO '${SOGO_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

mariadb "$SOGO_DB" <<SQL
DROP VIEW IF EXISTS sogo_view;

CREATE VIEW sogo_view
(
    c_uid,
    c_name,
    c_password,
    c_cn,
    mail
)
AS
SELECT
    email_utf8,
    email_utf8,
    password,
    email_utf8,
    email_utf8
FROM keyhelp.mail_users
WHERE login_enabled = 'Y';
SQL

###############################################################################
# SOGo package repository
###############################################################################

if [[ "$LANGUAGE" == "de" ]]; then
    log "Repository-Abhaengigkeiten installieren"
else
    log "Installing repository prerequisites"
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg openssl
install -d -m 0755 /etc/apt/keyrings

if [[ "$LANGUAGE" == "de" ]]; then
    log "SOGo-Repository fuer Debian 13 hinzufuegen"
else
    log "Adding SOGo Debian 13 repository"
fi

curl -fsSL \
    "https://keys.openpgp.org/vks/v1/by-fingerprint/74FFC6D72B925A34B5D356BDF8A27B36A6E2EAE9" \
    -o /etc/apt/keyrings/sogo.asc

cat > /etc/apt/sources.list.d/sogo.list <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/sogo.asc] https://packagingv2.sogo.nu/sogo-nightly-debian trixie main
EOF

apt-get update

###############################################################################
# Package installation
###############################################################################

if [[ "$LANGUAGE" == "de" ]]; then
    log "SOGo installieren"
else
    log "Installing SOGo"
fi

PACKAGES=(sogo)
if [[ "$ENABLE_ACTIVESYNC" == "yes" ]]; then
    PACKAGES+=(sogo-activesync)
fi
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"

###############################################################################
# Configuration backup
###############################################################################

if [[ -f /etc/sogo/sogo.conf ]]; then
    cp -a /etc/sogo/sogo.conf "$BACKUP_DIR/sogo.conf.original"
fi
if [[ -f /etc/apache2/conf-available/sogo.conf ]]; then
    cp -a /etc/apache2/conf-available/sogo.conf "$BACKUP_DIR/apache-sogo.conf.original"
fi

###############################################################################
# SOGo configuration
###############################################################################

if [[ "$LANGUAGE" == "de" ]]; then
    log "SOGo-Konfiguration schreiben"
else
    log "Writing SOGo configuration"
fi

cat > /etc/sogo/sogo.conf <<EOF
{
  SOGoProfileURL =
    "mysql://${SOGO_DB_USER}:${SOGO_DB_PASSWORD}@localhost:3306/${SOGO_DB}/sogo_user_profile";

  OCSFolderInfoURL =
    "mysql://${SOGO_DB_USER}:${SOGO_DB_PASSWORD}@localhost:3306/${SOGO_DB}/sogo_folder_info";

  OCSSessionsFolderURL =
    "mysql://${SOGO_DB_USER}:${SOGO_DB_PASSWORD}@localhost:3306/${SOGO_DB}/sogo_sessions_folder";

  OCSAdminURL =
    "mysql://${SOGO_DB_USER}:${SOGO_DB_PASSWORD}@localhost:3306/${SOGO_DB}/sogo_admin";

  SOGoUserSources = (
    {
      type = sql;
      id = keyhelp;
      displayName = "KeyHelp";
      viewURL =
        "mysql://${SOGO_DB_USER}:${SOGO_DB_PASSWORD}@localhost:3306/${SOGO_DB}/sogo_view";
      canAuthenticate = YES;
      isAddressBook = YES;
      userPasswordAlgorithm = blf-crypt;
    }
  );

  SOGoIMAPServer = "imap://127.0.0.1:143";
  SOGoSMTPServer = "smtp://127.0.0.1:25";
  SOGoMailingMechanism = smtp;

  NGImap4AuthMechanism = plain;
  SOGoForceExternalLoginWithEmail = YES;

  SOGoDraftsFolderName = Drafts;
  SOGoSentFolderName = Sent;
  SOGoTrashFolderName = Trash;
  SOGoJunkFolderName = Junk;

  SOGoPageTitle = "KeyHelp SOGo";
  SOGoLanguage = $([[ "$LANGUAGE" == "de" ]] && echo German || echo English);
  SOGoTimeZone = Europe/Berlin;

  WOPidFile = "/var/run/sogo/sogo.pid";
  WOLogFile = "/var/log/sogo/sogo.log";
EOF

if [[ "$ENABLE_SIEVE" == "yes" ]]; then
cat >> /etc/sogo/sogo.conf <<'EOF'

  SOGoSieveServer = "sieve://127.0.0.1:4190";
  SOGoSieveScriptsEnabled = YES;
EOF
fi

if [[ "$ENABLE_VACATION" == "yes" ]]; then
cat >> /etc/sogo/sogo.conf <<'EOF'
  SOGoVacationEnabled = YES;
EOF
fi

if [[ "$ENABLE_FORWARD" == "yes" ]]; then
cat >> /etc/sogo/sogo.conf <<'EOF'
  SOGoForwardEnabled = YES;
EOF
fi

cat >> /etc/sogo/sogo.conf <<'EOF'
}
EOF

chown root:sogo /etc/sogo/sogo.conf
chmod 640 /etc/sogo/sogo.conf

###############################################################################
# Apache integration
###############################################################################

if [[ "$LANGUAGE" == "de" ]]; then
    log "Apache Reverse Proxy konfigurieren"
else
    log "Configuring Apache reverse proxy"
fi

a2enmod proxy >/dev/null
a2enmod proxy_http >/dev/null
a2enmod headers >/dev/null

cat > /etc/apache2/conf-available/sogo.conf <<'EOF'
ProxyRequests Off
ProxyPreserveHost On

ProxyPass /SOGo http://127.0.0.1:20000/SOGo retry=0 timeout=360
ProxyPassReverse /SOGo http://127.0.0.1:20000/SOGo
EOF

if [[ "$ENABLE_ACTIVESYNC" == "yes" ]]; then
cat >> /etc/apache2/conf-available/sogo.conf <<'EOF'

ProxyPass /Microsoft-Server-ActiveSync \
  http://127.0.0.1:20000/SOGo/Microsoft-Server-ActiveSync
ProxyPassReverse /Microsoft-Server-ActiveSync \
  http://127.0.0.1:20000/SOGo/Microsoft-Server-ActiveSync
EOF
fi

cat >> /etc/apache2/conf-available/sogo.conf <<'EOF'

RequestHeader set "x-webobjects-server-port" "443"
RequestHeader set "x-webobjects-server-name" "%{HTTP_HOST}s"
RequestHeader set "x-webobjects-server-url" "https://%{HTTP_HOST}s"
RequestHeader set "x-webobjects-server-protocol" "HTTP/1.0"

Alias /SOGo.woa/WebServerResources/ \
  /usr/lib/x86_64-linux-gnu/GNUstep/SOGo/WebServerResources/

<Directory /usr/lib/x86_64-linux-gnu/GNUstep/SOGo/WebServerResources/>
    Require all granted
</Directory>
EOF

a2enconf sogo >/dev/null

###############################################################################
# Validate and restart
###############################################################################

if [[ "$LANGUAGE" == "de" ]]; then
    log "Apache-Konfiguration pruefen"
else
    log "Validating Apache configuration"
fi
apache2ctl configtest

if [[ "$LANGUAGE" == "de" ]]; then
    log "Dienste neu starten"
else
    log "Restarting services"
fi
systemctl restart sogo
systemctl reload apache2
sleep 3

###############################################################################
# Basic health checks
###############################################################################

if [[ "$LANGUAGE" == "de" ]]; then
    log "Health Checks ausfuehren"
else
    log "Running health checks"
fi

for svc in sogo apache2 postfix dovecot; do
    if systemctl is-active --quiet "$svc"; then
        if [[ "$LANGUAGE" == "de" ]]; then
            ok "$svc laeuft"
        else
            ok "$svc is running"
        fi
    else
        if [[ "$LANGUAGE" == "de" ]]; then
            warn "$svc ist nicht aktiv"
        else
            warn "$svc is not active"
        fi
    fi
done

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20000/SOGo/ || true)"
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    if [[ "$LANGUAGE" == "de" ]]; then
        ok "SOGo antwortet intern mit HTTP ${HTTP_CODE}"
    else
        ok "SOGo responds internally with HTTP ${HTTP_CODE}"
    fi
else
    warn "Unexpected internal SOGo HTTP status: ${HTTP_CODE}"
fi

USER_COUNT="$(mariadb "$SOGO_DB" -Nse "SELECT COUNT(*) FROM sogo_view" 2>/dev/null || echo 0)"
if [[ "$LANGUAGE" == "de" ]]; then
    ok "${USER_COUNT} aktivierte KeyHelp-Mailbox(en) fuer SOGo sichtbar"
else
    ok "${USER_COUNT} enabled KeyHelp mailbox(es) visible to SOGo"
fi

###############################################################################
# Result
###############################################################################

echo
printf '============================================================\n'
printf ' %s\n' "$(msg finished)"
printf '============================================================\n\n'
printf 'SOGo Web UI:\n  https://%s/SOGo\n\n' "$SERVER_FQDN"

if [[ "$ENABLE_ACTIVESYNC" == "yes" ]]; then
    printf 'ActiveSync endpoint:\n  https://%s/Microsoft-Server-ActiveSync\n\n' "$SERVER_FQDN"
fi

if [[ "$LANGUAGE" == "de" ]]; then
    printf 'SOGo DB-Zugangsdaten:\n  %s\n\n' "$CREDENTIAL_FILE"
    printf 'Konfigurations-Backup:\n  %s\n\n' "$BACKUP_DIR"
    printf 'WICHTIG:\n'
    printf '  - Fuer den Server-FQDN ein oeffentlich vertrauenswuerdiges TLS-Zertifikat konfigurieren.\n'
    printf '  - In KeyHelp: SSL/TLS-Zertifikate -> Serverdienste absichern -> Let\x27s Encrypt.\n'
    printf '  - Mail, Kalender, Kontakte und ActiveSync vor Produktiveinsatz testen.\n\n'
    printf 'Nutzung auf eigene Gefahr.\n'
else
    printf 'SOGo DB credentials:\n  %s\n\n' "$CREDENTIAL_FILE"
    printf 'Configuration backup:\n  %s\n\n' "$BACKUP_DIR"
    printf 'IMPORTANT:\n'
    printf '  - Configure a publicly trusted TLS certificate for the server FQDN.\n'
    printf '  - In KeyHelp use SSL/TLS certificates -> secure server services -> Let\x27s Encrypt.\n'
    printf '  - Test mail, calendar, contacts and ActiveSync before production use.\n\n'
    printf 'Use at your own risk.\n'
fi
