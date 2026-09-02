#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Debian 13 + KeyHelp + SOGo Installer
#
# DISCLAIMER:
# Use at your own risk. Always test on a non-production system first and create
# a complete backup before running this script. This project is not affiliated
# with KeyHelp, SOGo or their vendors. The script was created with the help of
# ChatGPT and tested on a Debian 13 + KeyHelp test installation.
#
# Adds SOGo groupware to an existing KeyHelp installation while keeping
# KeyHelp's Postfix, Dovecot, Rspamd and mailbox management intact.
#
# Profiles:
#   1) Minimal  - Webmail, calendar, contacts
#   2) Standard - Minimal + Sieve, vacation, forwarding
#   3) Full     - Standard + Exchange ActiveSync
#   4) Custom   - Select features individually
###############################################################################

readonly SCRIPT_VERSION="0.1.0"
readonly SOGO_DB="sogo"
readonly SOGO_DB_USER="sogo"
readonly CREDENTIAL_FILE="/root/.sogo-db-credentials"

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

trap 'printf "\n[ERROR] Installation failed at line %s.\n" "$LINENO" >&2' ERR

if [[ ${EUID} -ne 0 ]]; then
    die "Please run this installer as root."
fi

printf '\n============================================================\n'
printf ' Debian 13 + KeyHelp + SOGo Installer v%s\n' "$SCRIPT_VERSION"
printf '============================================================\n\n'
printf ' WARNING: Use at your own risk. Backup first.\n'
printf ' Created with the help of ChatGPT and tested on a test system.\n\n'

###############################################################################
# Pre-flight checks
###############################################################################

[[ -r /etc/os-release ]] || die "/etc/os-release not found."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] || \
    die "This installer currently supports Debian 13 only."

for cmd in mariadb apache2ctl postconf doveconf systemctl hostname; do
    command -v "$cmd" >/dev/null 2>&1 || \
        die "Required command '$cmd' not found. Is KeyHelp fully installed?"
done

mariadb -Nse "SHOW DATABASES" | grep -qx keyhelp || \
    die "KeyHelp database 'keyhelp' not found."

mariadb keyhelp -Nse "SHOW TABLES" | grep -qx mail_users || \
    die "KeyHelp table 'keyhelp.mail_users' not found."

for column in email_utf8 password login_enabled; do
    mariadb keyhelp -Nse "SHOW COLUMNS FROM mail_users LIKE '${column}'" | grep -q . || \
        die "Required KeyHelp column 'mail_users.${column}' not found. KeyHelp schema may have changed."
done

SERVER_FQDN="$(hostname -f 2>/dev/null || true)"
[[ "$SERVER_FQDN" == *.* ]] || die "No valid server FQDN detected. Configure the KeyHelp server hostname first."

echo "Detected FQDN: ${SERVER_FQDN}"

###############################################################################
# Profile selection
###############################################################################

echo
echo "Installation profile:"
echo "  [1] Minimal"
echo "      Webmail + calendar + contacts"
echo
echo "  [2] Standard"
echo "      Minimal + Sieve filters + vacation + forwarding"
echo
echo "  [3] Full (recommended)"
echo "      Standard + Exchange ActiveSync"
echo
echo "  [4] Custom"
echo

read -r -p "Selection [1-4, default: 3]: " PROFILE
PROFILE="${PROFILE:-3}"

ENABLE_SIEVE="no"
ENABLE_VACATION="no"
ENABLE_FORWARD="no"
ENABLE_ACTIVESYNC="no"

ask_yes_no() {
    local prompt="$1"
    local answer
    read -r -p "${prompt} [Y/n]: " answer
    [[ "${answer:-Y}" =~ ^[YyJj]$ ]]
}

case "$PROFILE" in
    1)
        ;;
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
        ask_yes_no "Enable Sieve filters?" && ENABLE_SIEVE="yes"
        ask_yes_no "Enable vacation messages?" && ENABLE_VACATION="yes"
        ask_yes_no "Enable forwarding in SOGo?" && ENABLE_FORWARD="yes"
        ask_yes_no "Install and expose ActiveSync?" && ENABLE_ACTIVESYNC="yes"
        ;;
    *)
        die "Invalid profile selection."
        ;;
esac

echo
echo "Selected features:"
printf '  Sieve:      %s\n' "$ENABLE_SIEVE"
printf '  Vacation:   %s\n' "$ENABLE_VACATION"
printf '  Forwarding: %s\n' "$ENABLE_FORWARD"
printf '  ActiveSync: %s\n' "$ENABLE_ACTIVESYNC"
echo

if ! ask_yes_no "Start installation?"; then
    echo "Cancelled."
    exit 0
fi

###############################################################################
# Backups and credentials
###############################################################################

BACKUP_DIR="/root/sogo-install-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
log "Backup directory: ${BACKUP_DIR}"

if [[ -f "$CREDENTIAL_FILE" ]]; then
    # Reuse the existing generated password on repeated runs.
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

log "Preparing SOGo database and live KeyHelp user view"

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

log "Installing repository prerequisites"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg openssl

install -d -m 0755 /etc/apt/keyrings

log "Adding SOGo Debian 13 repository"
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

log "Installing SOGo"
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

log "Writing SOGo configuration"

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

log "Configuring Apache reverse proxy"
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

log "Validating Apache configuration"
apache2ctl configtest

log "Restarting services"
systemctl restart sogo
systemctl reload apache2
sleep 3

###############################################################################
# Basic health checks
###############################################################################

log "Running health checks"

for svc in sogo apache2 postfix dovecot; do
    if systemctl is-active --quiet "$svc"; then
        ok "$svc is running"
    else
        warn "$svc is not active"
    fi
done

HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20000/SOGo/ || true)"
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    ok "SOGo responds internally with HTTP ${HTTP_CODE}"
else
    warn "Unexpected internal SOGo HTTP status: ${HTTP_CODE}"
fi

USER_COUNT="$(mariadb "$SOGO_DB" -Nse "SELECT COUNT(*) FROM sogo_view" 2>/dev/null || echo 0)"
ok "${USER_COUNT} enabled KeyHelp mailbox(es) visible to SOGo"

###############################################################################
# Result
###############################################################################

echo
printf '============================================================\n'
printf ' Installation finished\n'
printf '============================================================\n\n'
printf 'SOGo Web UI:\n  https://%s/SOGo\n\n' "$SERVER_FQDN"

if [[ "$ENABLE_ACTIVESYNC" == "yes" ]]; then
    printf 'ActiveSync endpoint:\n  https://%s/Microsoft-Server-ActiveSync\n\n' "$SERVER_FQDN"
fi

printf 'SOGo DB credentials:\n  %s\n\n' "$CREDENTIAL_FILE"
printf 'Configuration backup:\n  %s\n\n' "$BACKUP_DIR"
printf 'IMPORTANT:\n'
printf '  - Configure a publicly trusted TLS certificate for the server FQDN.\n'
printf '  - In KeyHelp use SSL/TLS certificates -> secure server services -> Let\x27s Encrypt.\n'
printf '  - Test mail, calendar, contacts and ActiveSync before production use.\n\n'
printf 'Use at your own risk.\n'
