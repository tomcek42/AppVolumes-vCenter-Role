# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden hier dokumentiert.

Das Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/),
und das Projekt folgt [Semantic Versioning](https://semver.org/lang/de/).

## [1.1.0] - 2026-07-02

### Hinzugefügt
- Interaktive Nachinstallation fehlender PowerShell-Module im Preflight: Bei
  Zustimmung wird geprüft, ob die Konsole als Administrator läuft, und das Modul
  systemweit (`Scope AllUsers`) installiert.
- Angebot, bei nicht erhöhter Konsole eine erhöhte Konsole für die Installation
  zu starten; alternativ Per-User-Installation (`Scope CurrentUser`).
- Erneute Verfügbarkeitsprüfung per `Get-Module -ListAvailable` nach jedem
  Installationsversuch.
- Abfrage beim Start, ob eine vorhandene `config.json` als Vorgabe verwendet
  werden soll; das Produktmenü schlägt die darin konfigurierten Produkte als
  Standardauswahl vor.

## [1.0.0] - 2026-06-30

### Hinzugefügt
- Erste Version: eigenständiges Skript zum Anlegen der benutzerdefinierten
  vCenter-Rollen für Omnissa App Volumes und Horizon VDI (Instant Clone),
  menügeführt für ein Produkt oder beide zusammen.
- Optionale Erstellung/Zuweisung eines Dienstkontos und Rollenzuweisung an der
  vCenter-Wurzel (propagiert).
- Speicherung der Vorgaben in `config.json`, verschlüsselte Ablage der
  Anmeldedaten (Windows DPAPI) sowie vCenter-8.0-Versionsprüfung.

[1.1.0]: https://github.com/tomcek42/OmnissaHorizon-vCenterRolesPermissions/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/tomcek42/OmnissaHorizon-vCenterRolesPermissions/releases/tag/v1.0.0
