# Debian 13 + KeyHelp + SOGo Installer

[Deutsch](#deutsch) · [English](#english)

---

# Deutsch

Interaktiver Installer, um **SOGo Groupware** auf einer bestehenden **KeyHelp-Installation unter Debian 13** zu ergänzen.

KeyHelp bleibt weiterhin für Mailserver, Domains, Postfächer, Postfix, Dovecot, Rspamd und die Administration zuständig. SOGo wird als zusätzliche Webmail-/Groupware-Oberfläche darübergelegt.

## ⚠️ Hinweis / Haftungsausschluss

> **Benutzung auf eigene Gefahr.**
>
> Vor der Installation bitte ein vollständiges Backup bzw. einen Snapshot erstellen und die Integration möglichst zuerst auf einem Testsystem ausprobieren.
>
> Dieses Projekt steht in keiner offiziellen Verbindung zu KeyHelp, Keyweb oder SOGo.
>
> Das Script wurde **mit Hilfe von ChatGPT erstellt** und anschließend von mir auf einer eigenen Debian-13-/KeyHelp-Testinstallation praktisch getestet. Es gibt keine Garantie, dass es mit jeder KeyHelp-/SOGo-Version oder nach zukünftigen Updates unverändert funktioniert.

## Was das Script macht

Der bestehende KeyHelp-Mailstack bleibt erhalten:

- Postfix
- Dovecot
- Rspamd
- MariaDB
- Apache
- Domain- und Postfachverwaltung über KeyHelp

SOGo erhält die aktivierten KeyHelp-Postfächer über eine Live-SQL-View auf `keyhelp.mail_users`. Dadurch ist **kein separater Benutzer-Sync** notwendig. Neue aktivierte Mailboxen in KeyHelp stehen direkt auch in SOGo zur Verfügung.

## Installationsprofile

### 1. Minimal
- Webmail
- Kalender
- Kontakte

### 2. Standard
Zusätzlich:
- Sieve-Filter
- Abwesenheitsnotiz / Vacation
- Weiterleitungen

### 3. Full
Zusätzlich:
- Exchange ActiveSync
- Apache-Endpunkt `/Microsoft-Server-ActiveSync`

### 4. Benutzerdefiniert
Optionale Funktionen können einzeln ausgewählt werden.

## Von mir getestet

Getestet wurde die Integration auf einer frischen Testinstallation mit unter anderem:

- Debian 13 (Trixie)
- KeyHelp
- Apache 2.4
- Postfix 3.10
- Dovecot 2.4
- MariaDB 11
- SOGo 5.12.x
- `sogo-activesync`

Folgende Funktionen habe ich erfolgreich getestet:

- Login mit einem bestehenden KeyHelp-Mailkonto
- SOGo Webmail
- Mail-Empfang über den bestehenden KeyHelp-/Postfix-/Dovecot-Stack
- Mail-Versand über den bestehenden KeyHelp-/Postfix-Stack
- Kalender
- Kontakte
- Sieve / Filter
- Vacation / Abwesenheitsnotiz
- Weiterleitungen
- ActiveSync-Endpunkt und Authentifizierung
- ActiveSync auf einem Mobilgerät nach Umstellung des Serverzertifikats auf ein öffentlich vertrauenswürdiges Zertifikat
- vollständige Entfernung von SOGo und anschließende Neuinstallation über dieses Script

Der Installer lief bei diesem Clean-Test bis zu den Health Checks vollständig durch und erkannte die vorhandenen KeyHelp-Mailboxen korrekt.

## Installation

KeyHelp muss bereits installiert sein und funktionieren.

```bash
git clone https://github.com/worker2000/debian13-keyhelp-SOGo.git
cd debian13-keyhelp-SOGo
chmod +x install.sh
./install.sh
```

Beim Start kann die Sprache **Deutsch oder English** gewählt werden. Danach wird das gewünschte Installationsprofil abgefragt.

## Authentifizierung

KeyHelp bleibt die führende Benutzerverwaltung:

```text
KeyHelp
   |
   +-- keyhelp.mail_users
            |
            +-- sogo_view
                    |
                    +-- SOGo
```

Es werden keine Benutzer in eine zweite Benutzerverwaltung kopiert.

Die getestete KeyHelp-Installation verwendet bcrypt-Passworthashes (`$2y$...`), die über SOGo mit `blf-crypt` eingebunden werden.

## URLs

SOGo:

```text
https://SERVER-FQDN/SOGo
```

Mit ActiveSync:

```text
https://SERVER-FQDN/Microsoft-Server-ActiveSync
```

## TLS / Let's Encrypt

Für ActiveSync und viele mobile Clients wird ein öffentlich vertrauenswürdiges TLS-Zertifikat benötigt.

In KeyHelp kann der Server-FQDN über die SSL/TLS-Einstellungen für die Serverdienste mit einem Let's-Encrypt-Zertifikat abgesichert werden. Der FQDN muss vorher öffentlich korrekt auf den Server zeigen.

## Hinweise

- Vorher Backup/Snapshot erstellen.
- Updates von KeyHelp oder SOGo zuerst auf einem Testsystem prüfen.
- Das Script installiert **nicht KeyHelp selbst**.
- Bestehende SOGo-/Apache-Konfigurationen werden vor dem Überschreiben gesichert.
- Die SOGo-Datenbankzugangsdaten werden automatisch erzeugt und root-only unter `/root/.sogo-db-credentials` gespeichert.

---

# English

Interactive installer for adding **SOGo Groupware** to an existing **KeyHelp installation on Debian 13**.

KeyHelp remains responsible for mail domains, mailboxes, Postfix, Dovecot, Rspamd and administration. SOGo is added as an additional webmail/groupware frontend.

## ⚠️ Disclaimer

> **Use at your own risk.**
>
> Create a complete backup or snapshot before installation and preferably test the integration on a non-production system first.
>
> This project is not officially affiliated with KeyHelp, Keyweb or SOGo.
>
> The script was **created with the help of ChatGPT** and then practically tested by me on my own Debian 13 + KeyHelp test installation. There is no guarantee that it will continue to work unchanged with every KeyHelp/SOGo version or future update.

## What the installer does

The existing KeyHelp mail stack remains intact:

- Postfix
- Dovecot
- Rspamd
- MariaDB
- Apache
- domain and mailbox management through KeyHelp

SOGo reads enabled KeyHelp mailboxes through a live SQL view on `keyhelp.mail_users`, so **no separate user synchronization job is required**. New enabled KeyHelp mailboxes are directly available in SOGo.

## Installation profiles

### 1. Minimal
- Webmail
- Calendar
- Contacts

### 2. Standard
Additionally:
- Sieve filters
- Vacation / out-of-office
- Forwarding

### 3. Full
Additionally:
- Exchange ActiveSync
- Apache endpoint `/Microsoft-Server-ActiveSync`

### 4. Custom
Choose optional features individually.

## Tested by me

The integration was tested on a fresh test installation including:

- Debian 13 (Trixie)
- KeyHelp
- Apache 2.4
- Postfix 3.10
- Dovecot 2.4
- MariaDB 11
- SOGo 5.12.x
- `sogo-activesync`

I successfully tested:

- login with an existing KeyHelp mailbox
- SOGo webmail
- incoming mail via the existing KeyHelp/Postfix/Dovecot stack
- outgoing mail via the existing KeyHelp/Postfix stack
- calendar
- contacts
- Sieve / filters
- vacation / out-of-office
- forwarding
- ActiveSync endpoint and authentication
- mobile ActiveSync after switching the server certificate to a publicly trusted certificate
- complete removal of SOGo followed by a fresh reinstall using this installer

The installer completed the clean-install test including all health checks and correctly detected the existing KeyHelp mailboxes.

## Installation

KeyHelp must already be installed and working.

```bash
git clone https://github.com/worker2000/debian13-keyhelp-SOGo.git
cd debian13-keyhelp-SOGo
chmod +x install.sh
./install.sh
```

At startup you can choose **Deutsch or English**. The installer then asks which installation profile should be used.

## Authentication

KeyHelp remains the source of truth for mail users:

```text
KeyHelp
   |
   +-- keyhelp.mail_users
            |
            +-- sogo_view
                    |
                    +-- SOGo
```

Users are not copied into a second user database.

The tested KeyHelp installation uses bcrypt password hashes (`$2y$...`), which are integrated into SOGo using `blf-crypt`.

## URLs

SOGo:

```text
https://SERVER-FQDN/SOGo
```

With ActiveSync enabled:

```text
https://SERVER-FQDN/Microsoft-Server-ActiveSync
```

## TLS / Let's Encrypt

A publicly trusted TLS certificate is required for ActiveSync and many mobile clients.

KeyHelp can protect the server FQDN with a Let's Encrypt certificate through its SSL/TLS server-service certificate settings. Make sure the FQDN resolves publicly to the server first.

## Notes

- Create a backup/snapshot first.
- Test KeyHelp and SOGo updates on a non-production system first.
- The installer does **not** install KeyHelp itself.
- Existing SOGo/Apache configuration is backed up before replacement.
- SOGo database credentials are generated automatically and stored root-only in `/root/.sogo-db-credentials`.

## Feedback

This is a community/experimental integration. Feedback about other KeyHelp versions, clean installs, upgrades and mobile clients is welcome.
