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

## Neue Sicherheitsmodi

### Nur prüfen – ohne Änderungen

```bash
./install.sh --check
```

Der Check-Modus verändert **nichts** und prüft unter anderem Debian 13, KeyHelp-Schema, Dienste, vorhandene SOGo-Reste, Ports, Mailbox-Anzahl, FQDN und TLS-Zertifikat.

### SOGo wieder entfernen

```bash
./install.sh --uninstall
```

Der Uninstall-Modus entfernt die durch dieses Projekt eingerichtete SOGo-Integration wieder und lässt **KeyHelp, Postfix, Dovecot, Rspamd, Domains und Mailboxen unangetastet**.

## Adressbuch-Sichtbarkeit pro Mailbox

Zusätzlich gibt es `directory.sh` zur Verwaltung der Sichtbarkeit einzelner KeyHelp-Mailboxen im gemeinsamen SOGo-Verzeichnis.

**Standard ist PRIVATE.** Eine Adresse wird erst nach expliziter Freigabe für das Verzeichnis markiert.

```bash
chmod +x directory.sh
./directory.sh init
./directory.sh list
./directory.sh show bjoern@example.com
./directory.sh hide secret@example.com
./directory.sh status bjoern@example.com
```

Beispielziel:

- `bjoern@familieflessing.de` → sichtbar innerhalb der eigenen SOGo-Domain
- `erotik@familieflessing.de` → privat / nicht im Verzeichnis

Wichtig: Die per-Mailbox-Freigabe ist bereits als Verwaltungsschicht vorhanden. Die **Domain-Isolation selbst wird bewusst noch nicht automatisch durch den Installer aktiviert**, weil SOGos Multi-Domain-Modus interne Benutzerkennungen beeinflussen kann. Diese Funktion soll zuerst auf einer frischen Testinstallation validiert werden, bevor sie als sicherer Installer-Default übernommen wird.

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
- Mail-Empfang
- Mail-Versand
- Kalender
- Kontakte
- Sieve / Filter
- Vacation / Abwesenheitsnotiz
- Weiterleitungen
- ActiveSync-Endpunkt und Authentifizierung
- ActiveSync auf einem Mobilgerät
- vollständige Entfernung von SOGo und anschließende Neuinstallation über dieses Script

## Installation

```bash
git clone https://github.com/worker2000/debian13-keyhelp-SOGo.git
cd debian13-keyhelp-SOGo
chmod +x install.sh
./install.sh --check
./install.sh
```

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

```text
https://SERVER-FQDN/SOGo
https://SERVER-FQDN/Microsoft-Server-ActiveSync
```

## TLS / Let's Encrypt

Für ActiveSync und viele mobile Clients wird ein öffentlich vertrauenswürdiges TLS-Zertifikat benötigt. In KeyHelp kann der Server-FQDN über die SSL/TLS-Einstellungen für die Serverdienste mit einem Let's-Encrypt-Zertifikat abgesichert werden.

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
> The script was **created with the help of ChatGPT** and then practically tested by me on my own Debian 13 + KeyHelp test installation.

## Installation profiles

1. Minimal – Webmail, calendar, contacts
2. Standard – plus Sieve, vacation and forwarding
3. Full – plus Exchange ActiveSync
4. Custom – choose optional features individually

## Safety modes

```bash
./install.sh --check
./install.sh --uninstall
```

`--check` is read-only. `--uninstall` removes the SOGo integration while keeping the KeyHelp mail stack intact.

## Per-mailbox directory visibility

`directory.sh` manages which KeyHelp mailboxes are eligible to appear in the SOGo shared directory.

**Default is PRIVATE.** A mailbox is only marked visible after explicit opt-in.

```bash
chmod +x directory.sh
./directory.sh init
./directory.sh list
./directory.sh show user@example.com
./directory.sh hide secret@example.com
./directory.sh status user@example.com
```

Target behavior:

- `user@example.com` → visible inside its own SOGo domain
- `secret@example.com` → private / hidden from the directory

Important: per-mailbox visibility management is implemented, but **domain isolation is intentionally not enabled automatically yet**. SOGo multi-domain mode can affect internal user identifiers, so it should first be validated on a fresh test installation before becoming an installer default.

## Tested by me

Successfully tested on Debian 13 + KeyHelp with SOGo 5.12.x, including webmail, incoming/outgoing mail, calendar, contacts, Sieve, vacation, forwarding, ActiveSync and a complete uninstall/reinstall cycle.

## Installation

```bash
git clone https://github.com/worker2000/debian13-keyhelp-SOGo.git
cd debian13-keyhelp-SOGo
chmod +x install.sh
./install.sh --check
./install.sh
```

## Feedback

This is a community/experimental integration. Feedback about other KeyHelp versions, clean installs, upgrades and mobile clients is welcome.
