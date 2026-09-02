#!/usr/bin/env bash
set -Eeuo pipefail

# KeyHelp + SOGo directory visibility manager
# Usage:
#   ./directory.sh init
#   ./directory.sh list [domain]
#   ./directory.sh show user@example.com
#   ./directory.sh hide user@example.com
#   ./directory.sh status user@example.com
#
# Visibility is PRIVATE by default. This helper only manages which KeyHelp
# mailboxes are eligible for the SOGo shared directory. Domain isolation is
# handled by the SOGo multi-domain configuration and must be enabled separately.

DB="sogo"
TABLE="sogo_directory_visibility"

[[ ${EUID} -eq 0 ]] || { echo "Run as root / Bitte als root ausfuehren." >&2; exit 1; }
command -v mariadb >/dev/null 2>&1 || { echo "mariadb not found" >&2; exit 1; }

init_table() {
  mariadb "$DB" <<'SQL'
CREATE TABLE IF NOT EXISTS sogo_directory_visibility (
  email VARCHAR(320) NOT NULL PRIMARY KEY,
  visible TINYINT(1) NOT NULL DEFAULT 0,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL
  echo "Visibility table ready. New addresses are private by default."
}

mailbox_exists() {
  local email="$1"
  mariadb keyhelp -Nse "SELECT COUNT(*) FROM mail_users WHERE email_utf8='$(printf "%s" "$email" | sed "s/'/''/g")' AND login_enabled='Y'" | grep -qx '1'
}

set_visibility() {
  local email="$1"
  local value="$2"
  init_table >/dev/null
  mailbox_exists "$email" || { echo "Mailbox not found or disabled in KeyHelp: $email" >&2; exit 1; }
  local esc
  esc="$(printf "%s" "$email" | sed "s/'/''/g")"
  mariadb "$DB" -e "INSERT INTO ${TABLE} (email,visible) VALUES ('${esc}',${value}) ON DUPLICATE KEY UPDATE visible=VALUES(visible);"
  if [[ "$value" == "1" ]]; then
    echo "VISIBLE inside its SOGo domain: $email"
  else
    echo "PRIVATE: $email"
  fi
}

list_entries() {
  local domain="${1:-}"
  init_table >/dev/null
  local where=""
  if [[ -n "$domain" ]]; then
    local esc
    esc="$(printf "%s" "$domain" | sed "s/'/''/g")"
    where="AND SUBSTRING_INDEX(mu.email_utf8,'@',-1)='${esc}'"
  fi
  mariadb --table -e "
    SELECT
      mu.email_utf8 AS email,
      SUBSTRING_INDEX(mu.email_utf8,'@',-1) AS domain,
      IF(COALESCE(v.visible,0)=1,'VISIBLE','PRIVATE') AS directory
    FROM keyhelp.mail_users mu
    LEFT JOIN ${DB}.${TABLE} v ON v.email=mu.email_utf8
    WHERE mu.login_enabled='Y' ${where}
    ORDER BY domain,email;"
}

status_entry() {
  local email="$1"
  init_table >/dev/null
  mailbox_exists "$email" || { echo "Mailbox not found or disabled in KeyHelp: $email" >&2; exit 1; }
  local esc
  esc="$(printf "%s" "$email" | sed "s/'/''/g")"
  local state
  state="$(mariadb "$DB" -Nse "SELECT COALESCE((SELECT visible FROM ${TABLE} WHERE email='${esc}'),0)")"
  [[ "$state" == "1" ]] && echo "VISIBLE: $email" || echo "PRIVATE: $email"
}

case "${1:-}" in
  init) init_table ;;
  list) list_entries "${2:-}" ;;
  show) [[ -n "${2:-}" ]] || { echo "Usage: $0 show user@example.com" >&2; exit 1; }; set_visibility "$2" 1 ;;
  hide) [[ -n "${2:-}" ]] || { echo "Usage: $0 hide user@example.com" >&2; exit 1; }; set_visibility "$2" 0 ;;
  status) [[ -n "${2:-}" ]] || { echo "Usage: $0 status user@example.com" >&2; exit 1; }; status_entry "$2" ;;
  *)
    cat <<EOF
Usage / Verwendung:
  $0 init
  $0 list [domain]
  $0 show user@example.com
  $0 hide user@example.com
  $0 status user@example.com

Default / Standard: PRIVATE
EOF
    exit 1
    ;;
esac
