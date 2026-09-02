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
#
# Modes:
#   ./install.sh             Interactive installation
#   ./install.sh --check     Read-only pre-flight check, changes nothing
#   ./install.sh --uninstall Remove this SOGo integration, keep KeyHelp intact
###############################################################################

readonly SCRIPT_VERSION="0.3.0"
readonly SOGO_DB="sogo"
readonly SOGO_DB_USER="sogo"
readonly CREDENTIAL_FILE="/root/.sogo-db-credentials"
readonly APACHE_SOGO_CONF="/etc/apache2/conf-available/sogo.conf"
readonly SOGO_REPO_FILE="/etc/apt/sources.list.d/sogo.list"
readonly SOGO_KEY_FILE="/etc/apt/keyrings/sogo.asc"

LANGUAGE="de"
MODE="install"

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

trap 'printf "\n[ERROR] Failed at line %s.\n" "$LINENO" >&2' ERR

usage() {
    cat <<'EOF'
Usage / Verwendung:
  ./install.sh              Interactive installation / Interaktive Installation
  ./install.sh --check      Read-only pre-flight check / Nur pruefen, nichts aendern
  ./install.sh --uninstall  Remove SOGo integration / SOGo-Integration entfernen
  ./install.sh --help       Show this help / Diese Hilfe anzeigen
EOF
}

case "${1:-}" in
    "") MODE="install" ;;
    --check) MODE="check" ;;
    --uninstall) MODE="uninstall" ;;
    --help|-h) usage; exit 0 ;;
    *) usage; exit 1 ;;
esac

if [[ ${EUID} -ne 0 ]]; then
    die "Please run this script as root. / Bitte als root ausfuehren."
fi

printf '\n============================================================\n'
printf ' Debian 13 + KeyHelp + SOGo Installer v%s\n' "$SCRIPT_VERSION"
printf '============================================================\n\n'
printf ' Language / Sprache:\n'
printf '   [1] Deutsch\n'
printf '   [2] English\n\n'
read -r -p "Selection / Auswahl [1-2, default/Standard: 1]: " LANG_SELECT
case "${LANG_SELECT:-1}" in
    2) LANGUAGE="en" ;;
    *) LANGUAGE="de" ;;
esac

say() {
    local de="$1"
    local en="$2"
    if [[ "$LANGUAGE" == "de" ]]; then printf '%s\n' "$de"; else printf '%s\n' "$en"; fi
}

ask_yes_no() {
    local de="$1"
    local en="$2"
    local answer
    if [[ "$LANGUAGE" == "de" ]]; then
        read -r -p "${de} [J/n]: " answer
        [[ "${answer:-J}" =~ ^[JjYy]$ ]]
    else
        read -r -p "${en} [Y/n]: " answer
        [[ "${answer:-Y}" =~ ^[YyJj]$ ]]
    fi
}

if [[ "$LANGUAGE" == "de" ]]; then
    echo
    echo "WARNUNG: Nutzung auf eigene Gefahr. Vorher Backup/Snapshot erstellen."
    echo "Dieses Script wurde mit Hilfe von ChatGPT erstellt und vom Repository-Inhaber"
    echo "auf einer Debian-13-/KeyHelp-Testinstallation praktisch getestet."
else
    echo
    echo "WARNING: Use at your own risk. Create a backup/snapshot first."
    echo "This script was created with the help of ChatGPT and practically tested by"
    echo "the repository owner on a Debian 13 + KeyHelp test installation."
fi

echo

###############################################################################
# Shared read-only checks
###############################################################################

basic_keyhelp_checks() {
    [[ -r /etc/os-release ]] || die "/etc/os-release not found."
    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]]; then
        ok "Debian 13 detected"
    else
        die "This script currently supports Debian 13 only. / Dieses Script unterstuetzt aktuell nur Debian 13."
    fi

    for cmd in mariadb apache2ctl postconf doveconf systemctl hostname; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command '$cmd' not found. Is KeyHelp fully installed?"
    done

    mariadb -Nse "SHOW DATABASES" | grep -qx keyhelp || die "KeyHelp database 'keyhelp' not found."
    ok "KeyHelp database found"

    mariadb keyhelp -Nse "SHOW TABLES" | grep -qx mail_users || die "KeyHelp table 'keyhelp.mail_users' not found."
    ok "KeyHelp mail_users table found"

    for column in email_utf8 password login_enabled; do
        mariadb keyhelp -Nse "SHOW COLUMNS FROM mail_users LIKE '${column}'" | grep -q . || \
            die "Required KeyHelp column 'mail_users.${column}' not found. KeyHelp schema may have changed."
    done
    ok "Required KeyHelp mail_users columns found"

    SERVER_FQDN="$(hostname -f 2>/dev/null || true)"
    [[ "$SERVER_FQDN" == *.* ]] || die "No valid server FQDN detected."
    ok "FQDN: ${SERVER_FQDN}"
}

###############################################################################
# --check: strictly read-only
###############################################################################

run_check() {
    say "Nur-Lese-Systempruefung - es werden KEINE Aenderungen vorgenommen." \
        "Read-only system check - NO changes will be made."

    log "KeyHelp / OS"
    basic_keyhelp_checks

    log "Services / Dienste"
    for svc in apache2 postfix dovecot mariadb; do
        if systemctl is-active --quiet "$svc"; then
            ok "$svc is running"
        else
            warn "$svc is not active"
        fi
    done

    log "Existing SOGo state / Vorhandener SOGo-Stand"
    if dpkg-query -W -f='${Status}\n' sogo 2>/dev/null | grep -q 'install ok installed'; then
        warn "Package 'sogo' is already installed"
    else
        ok "SOGo package is not installed"
    fi

    if dpkg-query -W -f='${Status}\n' sogo-activesync 2>/dev/null | grep -q 'install ok installed'; then
        warn "Package 'sogo-activesync' is already installed"
    else
        ok "sogo-activesync package is not installed"
    fi

    [[ -e /etc/sogo/sogo.conf ]] && warn "/etc/sogo/sogo.conf already exists" || ok "No existing /etc/sogo/sogo.conf"
    [[ -e "$APACHE_SOGO_CONF" ]] && warn "$APACHE_SOGO_CONF already exists" || ok "No existing Apache SOGo config"
    [[ -e "$SOGO_REPO_FILE" ]] && info "SOGo repository file already exists" || ok "No existing SOGo repository file"

    if mariadb -Nse "SHOW DATABASES" | grep -qx "$SOGO_DB"; then
        warn "MariaDB database '${SOGO_DB}' already exists"
    else
        ok "MariaDB database '${SOGO_DB}' does not exist"
    fi

    if mariadb -Nse "SELECT User FROM mysql.user WHERE User='${SOGO_DB_USER}' AND Host='localhost'" 2>/dev/null | grep -qx "$SOGO_DB_USER"; then
        warn "MariaDB user '${SOGO_DB_USER}'@'localhost' already exists"
    else
        ok "MariaDB user '${SOGO_DB_USER}'@'localhost' does not exist"
    fi

    log "Ports"
    if command -v ss >/dev/null 2>&1; then
        if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)20000$'; then
            warn "TCP port 20000 is already in use"
        else
            ok "TCP port 20000 is free"
        fi

        if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)4190$'; then
            ok "Sieve port 4190 is listening"
        else
            warn "Sieve port 4190 is not listening; Sieve/Vacation/Forward may not work"
        fi
    else
        info "Command 'ss' not available; port checks skipped"
    fi

    log "KeyHelp mailboxes"
    local user_count
    user_count="$(mariadb keyhelp -Nse "SELECT COUNT(*) FROM mail_users WHERE login_enabled='Y'" 2>/dev/null || echo 0)"
    ok "${user_count} enabled KeyHelp mailbox(es) found"

    log "TLS certificate"
    if command -v openssl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        local cert_info
        cert_info="$(timeout 8 openssl s_client -connect "${SERVER_FQDN}:443" -servername "$SERVER_FQDN" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null || true)"
        if [[ -n "$cert_info" ]]; then
            printf '%s\n' "$cert_info"
        else
            warn "Could not inspect TLS certificate on ${SERVER_FQDN}:443"
        fi
    else
        info "openssl/timeout unavailable; TLS inspection skipped"
    fi

    echo
    say "Pruefung abgeschlossen. Es wurden keine Dateien, Pakete, Datenbanken oder Dienste veraendert." \
        "Check complete. No files, packages, databases or services were changed."
}

###############################################################################
# --uninstall
###############################################################################

run_uninstall() {
    say "Dieser Modus entfernt nur die von diesem Projekt eingerichtete SOGo-Integration." \
        "This mode removes only the SOGo integration installed by this project."
    say "KeyHelp, Postfix, Dovecot, Rspamd, Domains und Mailboxen bleiben erhalten." \
        "KeyHelp, Postfix, Dovecot, Rspamd, domains and mailboxes are kept intact."
    echo

    if ! ask_yes_no "SOGo-Integration wirklich entfernen?" "Really remove the SOGo integration?"; then
        say "Abgebrochen." "Cancelled."
        exit 0
    fi

    local backup_dir="/root/sogo-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"

    [[ -f /etc/sogo/sogo.conf ]] && cp -a /etc/sogo/sogo.conf "$backup_dir/sogo.conf" || true
    [[ -f "$APACHE_SOGO_CONF" ]] && cp -a "$APACHE_SOGO_CONF" "$backup_dir/apache-sogo.conf" || true
    [[ -f "$CREDENTIAL_FILE" ]] && cp -a "$CREDENTIAL_FILE" "$backup_dir/sogo-db-credentials" || true

    log "Stopping SOGo"
    systemctl stop sogo 2>/dev/null || true

    log "Removing Apache integration"
    a2disconf sogo >/dev/null 2>&1 || true
    rm -f "$APACHE_SOGO_CONF" /etc/apache2/conf-enabled/sogo.conf
    apache2ctl configtest
    systemctl reload apache2

    log "Removing SOGo packages"
    DEBIAN_FRONTEND=noninteractive apt-get purge -y sogo sogo-activesync || true

    log "Removing project SOGo database"
    if command -v mariadb >/dev/null 2>&1; then
        mariadb <<SQL
DROP DATABASE IF EXISTS \`${SOGO_DB}\`;
DROP USER IF EXISTS '${SOGO_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    fi

    log "Removing SOGo project files"
    rm -rf /etc/sogo /var/log/sogo /var/lib/sogo /var/run/sogo
    rm -f "$CREDENTIAL_FILE" "$SOGO_REPO_FILE" "$SOGO_KEY_FILE"

    echo
    say "SOGo-Integration entfernt." "SOGo integration removed."
    say "KeyHelp-Mailstack wurde nicht entfernt." "KeyHelp mail stack was not removed."
    printf 'Backup: %s\n' "$backup_dir"
    say "Hinweis: Abhaengigkeitsbibliotheken (z.B. SOPE) werden absichtlich nicht automatisch entfernt." \
        "Note: dependency libraries (for example SOPE) are intentionally not auto-removed."
}

if [[ "$MODE" == "check" ]]; then
    run_check
    exit 0
fi

if [[ "$MODE" == "uninstall" ]]; then
    run_uninstall
    exit 0
fi

###############################################################################
# Interactive installation
###############################################################################

basic_keyhelp_checks

say "WARNUNG: Nutzung auf eigene Gefahr. Vorher Backup/Snapshot erstellen." \
    "WARNING: Use at your own risk. Create a backup/snapshot first."

###############################################################################
# Profile selection
###############################################################################

echo
say "Installationsprofil:" "Installation profile:"
echo "  [1] Minimal"
say "      Webmail + Kalender + Kontakte" "      Webmail + calendar + contacts"
echo
echo "  [2] Standard"
say "      Minimal + Sieve-Filter + Abwesenheit + Weiterleitungen" \
    "      Minimal + Sieve filters + vacation + forwarding"
echo
echo "  [3] Full"
say "      Standard + Exchange ActiveSync" "      Standard + Exchange ActiveSync"
echo
echo "  [4] Custom / Benutzerdefiniert"
say "      Optionale Funktionen einzeln auswaehlen" "      Choose optional features individually"
echo

if [[ "$LANGUAGE" == "de" ]]; then
    read -r -p "Auswahl [1-4, Standard: 3]: " PROFILE
else
    read -r -p "Selection [1-4, default: 3]: " PROFILE
fi
PROFILE="${PROFILE:-3}"

ENABLE_SIEVE="no"
ENABLE_VACATION="no"
ENABLE_FORWARD="no"
ENABLE_ACTIVESYNC="no"

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
        ask_yes_no "Sieve-Filter aktivieren?" "Enable Sieve filters?" && ENABLE_SIEVE="yes"
        ask_yes_no "Abwesenheitsnotizen aktivieren?" "Enable vacation messages?" && ENABLE_VACATION="yes"
        ask_yes_no "Weiterleitungen in SOGo aktivieren?" "Enable forwarding in SOGo?" && ENABLE_FORWARD="yes"
        ask_yes_no "ActiveSync installieren und bereitstellen?" "Install and expose ActiveSync?" && ENABLE_ACTIVESYNC="yes"
        ;;
    *) die "Invalid profile selection. / Ungueltige Auswahl." ;;
esac

echo
say "Ausgewaehlte Funktionen:" "Selected features:"
printf '  Sieve:      %s\n' "$ENABLE_SIEVE"
printf '  Vacation:   %s\n' "$ENABLE_VACATION"
printf '  Forwarding: %s\n' "$ENABLE_FORWARD"
printf '  ActiveSync: %s\n' "$ENABLE_ACTIVESYNC"
echo

if ! ask_yes_no "Installation starten?" "Start installation?"; then
    say "Abgebrochen." "Cancelled."
    exit 0
fi

###############################################################################
# Backups and credentials
###############################################################################

BACKUP_DIR="/root/sogo-install-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
log "Backup: ${BACKUP_DIR}"

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

log "Preparing SOGo database / SOGo-Datenbank vorbereiten"

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
(c_uid, c_name, c_password, c_cn, mail)
AS
SELECT email_utf8, email_utf8, password, email_utf8, email_utf8
FROM keyhelp.mail_users
WHERE login_enabled = 'Y';
SQL

###############################################################################
# SOGo repository and packages
###############################################################################

log "Installing repository prerequisites / Repository-Voraussetzungen"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg openssl
install -d -m 0755 /etc/apt/keyrings

log "Adding SOGo Debian 13 repository / SOGo-Repository hinzufuegen"
curl -fsSL \
    "https://keys.openpgp.org/vks/v1/by-fingerprint/74FFC6D72B925A34B5D356BDF8A27B36A6E2EAE9" \
    -o "$SOGO_KEY_FILE"

cat > "$SOGO_REPO_FILE" <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/sogo.asc] https://packagingv2.sogo.nu/sogo-nightly-debian trixie main
EOF

apt-get update

PACKAGES=(sogo)
if [[ "$ENABLE_ACTIVESYNC" == "yes" ]]; then
    PACKAGES+=(sogo-activesync)
fi
log "Installing SOGo / SOGo installieren"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"

###############################################################################
# Configuration backup
###############################################################################

[[ -f /etc/sogo/sogo.conf ]] && cp -a /etc/sogo/sogo.conf "$BACKUP_DIR/sogo.conf.original" || true
[[ -f "$APACHE_SOGO_CONF" ]] && cp -a "$APACHE_SOGO_CONF" "$BACKUP_DIR/apache-sogo.conf.original" || true

###############################################################################
# SOGo configuration
###############################################################################

log "Writing SOGo configuration / SOGo-Konfiguration schreiben"

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
  SOGoLanguage = German;
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
    echo '  SOGoVacationEnabled = YES;' >> /etc/sogo/sogo.conf
fi
if [[ "$ENABLE_FORWARD" == "yes" ]]; then
    echo '  SOGoForwardEnabled = YES;' >> /etc/sogo/sogo.conf
fi
cat >> /etc/sogo/sogo.conf <<'EOF'
}
EOF

chown root:sogo /etc/sogo/sogo.conf
chmod 640 /etc/sogo/sogo.conf

###############################################################################
# Apache integration
###############################################################################

log "Configuring Apache reverse proxy / Apache Reverse Proxy konfigurieren"
a2enmod proxy >/dev/null
a2enmod proxy_http >/dev/null
a2enmod headers >/dev/null

cat > "$APACHE_SOGO_CONF" <<'EOF'
ProxyRequests Off
ProxyPreserveHost On

ProxyPass /SOGo http://127.0.0.1:20000/SOGo retry=0 timeout=360
ProxyPassReverse /SOGo http://127.0.0.1:20000/SOGo
EOF

if [[ "$ENABLE_ACTIVESYNC" == "yes" ]]; then
cat >> "$APACHE_SOGO_CONF" <<'EOF'

ProxyPass /Microsoft-Server-ActiveSync \
  http://127.0.0.1:20000/SOGo/Microsoft-Server-ActiveSync
ProxyPassReverse /Microsoft-Server-ActiveSync \
  http://127.0.0.1:20000/SOGo/Microsoft-Server-ActiveSync
EOF
fi

cat >> "$APACHE_SOGO_CONF" <<'EOF'

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
# Validate, restart, health checks
###############################################################################

log "Validating Apache configuration / Apache-Konfiguration pruefen"
apache2ctl configtest

log "Restarting services / Dienste neu starten"
systemctl restart sogo
systemctl reload apache2
sleep 3

log "Health checks"
for svc in sogo apache2 postfix dovecot; do
    if systemctl is-active --quiet "$svc"; then ok "$svc is running"; else warn "$svc is not active"; fi
done

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20000/SOGo/ || true)"
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    ok "SOGo responds internally with HTTP ${HTTP_CODE}"
else
    warn "Unexpected internal SOGo HTTP status: ${HTTP_CODE}"
fi

USER_COUNT="$(mariadb "$SOGO_DB" -Nse "SELECT COUNT(*) FROM sogo_view" 2>/dev/null || echo 0)"
ok "${USER_COUNT} enabled KeyHelp mailbox(es) visible to SOGo"

echo
printf '============================================================\n'
say " Installation abgeschlossen" " Installation finished"
printf '============================================================\n\n'
printf 'SOGo Web UI:\n  https://%s/SOGo\n\n' "$SERVER_FQDN"
if [[ "$ENABLE_ACTIVESYNC" == "yes" ]]; then
    printf 'ActiveSync:\n  https://%s/Microsoft-Server-ActiveSync\n\n' "$SERVER_FQDN"
fi
printf 'SOGo DB credentials:\n  %s\n\n' "$CREDENTIAL_FILE"
printf 'Configuration backup:\n  %s\n\n' "$BACKUP_DIR"
say "WICHTIG: Fuer mobile Clients ein oeffentlich vertrauenswuerdiges TLS-Zertifikat verwenden." \
    "IMPORTANT: Use a publicly trusted TLS certificate for mobile clients."
say "Nutzung auf eigene Gefahr." "Use at your own risk."
