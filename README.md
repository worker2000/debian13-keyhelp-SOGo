# Debian 13 + KeyHelp + SOGo Installer

Interactive installer for adding **SOGo Groupware** to an existing **KeyHelp** installation on **Debian 13**.

KeyHelp remains responsible for the existing mail stack and mailbox administration. SOGo is added on top for webmail/groupware features.

## Disclaimer

> **Use at your own risk.**
>
> Always create a complete backup and test this on a non-production system first. This project is not affiliated with KeyHelp, Keyweb, SOGo or their vendors.
>
> The installer was **created with the help of ChatGPT** and tested on a Debian 13 + KeyHelp test installation. No warranty is provided that it will work with every KeyHelp or SOGo version or with future updates.

## What it does

The installer keeps the existing KeyHelp stack intact:

- Postfix
- Dovecot
- Rspamd
- MariaDB
- Apache
- mailbox/domain management in KeyHelp

SOGo uses a live SQL view on `keyhelp.mail_users`, so enabled KeyHelp mailboxes are directly available in SOGo without a separate synchronization job.

## Available profiles

### 1. Minimal

- Webmail
- Calendar
- Contacts

### 2. Standard

Everything from Minimal plus:

- Sieve filters
- Vacation / out-of-office
- Forwarding

### 3. Full

Everything from Standard plus:

- Exchange ActiveSync
- `/Microsoft-Server-ActiveSync` Apache proxy endpoint

### 4. Custom

Choose the optional features individually.

## Tested setup

The initial test setup used:

- Debian 13 (Trixie)
- KeyHelp
- Apache 2.4
- Postfix 3.10
- Dovecot 2.4
- MariaDB 11
- SOGo 5.12.x
- `sogo-activesync`

## Installation

KeyHelp must already be installed and working.

Clone the repository:

```bash
git clone https://github.com/worker2000/debian13-keyhelp-SOGo.git
cd debian13-keyhelp-SOGo
```

Make the installer executable:

```bash
chmod +x install.sh
```

Run as root:

```bash
./install.sh
```

The installer asks which profile should be installed. **Full** is the default.

## How authentication works

KeyHelp stays the source of truth for mail users.

The installer creates the SOGo database and a live SQL view similar to:

```text
KeyHelp
   |
   +-- keyhelp.mail_users
            |
            +-- sogo_view
                    |
                    +-- SOGo
```

New enabled mailboxes created in KeyHelp therefore become available to SOGo without copying users into a second user database.

The integration currently expects KeyHelp's mailbox password hashes to work with SOGo's `blf-crypt` setting, as observed on the tested installation.

## URLs

After installation, the expected URLs are:

```text
https://SERVER-FQDN/SOGo
```

With ActiveSync enabled:

```text
https://SERVER-FQDN/Microsoft-Server-ActiveSync
```

## TLS / Let's Encrypt

A publicly trusted TLS certificate is strongly recommended and effectively required for many mobile ActiveSync clients.

On KeyHelp, the server services can be protected with a Let's Encrypt certificate via the SSL/TLS certificate settings / server service certificate configuration.

Make sure the server FQDN resolves publicly to the server before requesting the certificate.

## Important notes

- Back up the server before installation.
- Test upgrades on a non-production system first.
- KeyHelp or SOGo updates may change database schemas, configuration formats or package behavior.
- The installer performs basic schema checks and saves existing SOGo/Apache configuration files before replacing them.
- SOGo database credentials are generated automatically and stored root-only in `/root/.sogo-db-credentials`.
- The script does **not** install KeyHelp itself.

## What was verified during the initial test

The following functions were successfully tested on the original test system:

- login with a KeyHelp mailbox
- SOGo webmail
- receiving mail via the existing KeyHelp Postfix/Dovecot stack
- sending mail through the existing KeyHelp Postfix stack
- calendar
- contacts
- Sieve-related settings
- vacation / forwarding options
- SOGo ActiveSync endpoint authentication
- mobile ActiveSync after switching the server service certificate to a publicly trusted certificate

## Feedback

This is currently an experimental/community integration. Reports about other KeyHelp versions, clean installations, upgrades and mobile clients are welcome.
