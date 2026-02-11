# Product Requirements Document (PRD) – CourtSwiss

## 1. Überblick
Dieses Dokument beschreibt die funktionalen und nicht-funktionalen Anforderungen für das MVP von CourtSwiss. Ziel ist eine reglement-konforme, benutzerfreundliche Interclub-App für Captains und Spieler:innen in der Schweiz.

## 2. Benutzerrollen
### 2.1 Captain
- Erstellt und verwaltet ein Team
- Erstellt Begegnungen (Fixtures)
- Sieht alle Verfügbarkeiten
- Erstellt und finalisiert Aufstellungen
- Verwaltet Ersatzspieler
- Erstellt Fahrgemeinschaften
- Verwaltet Spesen und Belege

### 2.2 Spieler:in
- Sieht Team und Begegnungen
- Gibt Verfügbarkeit an
- Kann Ersatzanfrage annehmen oder ablehnen
- Kann Fahrgemeinschaften beitreten
- Kann Zahlungsstatus bestätigen

## 3. Team-Management
### Anforderungen
- Ein Team gehört zu genau einer Saison
- Ein Team hat genau einen Captain
- Ein Spieler kann Mitglied in mehreren Teams sein
- Klassierung (R9–N1) ist Pflichtfeld
- Optionale Ranking-Feinzahl für Sortierung

## 4. Begegnung (Fixture)
### Attribute
- Gegner (Text)
- Datum & Uhrzeit
- Ort (Text / Koordinaten optional)
- Status: geplant | bestätigt | gespielt

### Anforderungen
- Begegnung ist immer genau einem Team zugeordnet
- Pro Begegnung existiert genau ein aktiver Planungsstatus

## 5. Verfügbarkeit
### Anforderungen
- Status: Ja | Nein | Vielleicht
- Standard = Vielleicht
- Änderung jederzeit möglich bis Aufstellung finalisiert ist
- Captain sieht Übersicht aller Antworten

## 6. Aufstellung (Einzel)
### Regeln
- Anzahl Einzel abhängig von Kategorie
- Automatische Sortierung nach Klassierung
- Beste Klassierung = Position 1
- Restliche verfügbare Spieler = Ersatzliste

### Captain-Rechte
- Manuelles Überschreiben erlaubt
- Warnhinweis bei Regelverletzung
- Finalisierung sperrt automatische Änderungen

## 7. Ersatzspieler-Logik
### Ablauf
1. Spieler sagt ab
2. System prüft Ersatzliste
3. Ersatz #1 erhält Anfrage
4. Keine Antwort oder Absage → Ersatz #2
5. Zusage → Spieler rückt nach

### Anforderungen
- Nur ein aktiver Ersatz-Request gleichzeitig
- Push-Benachrichtigung verpflichtend
- Zeitlimit pro Anfrage konfigurierbar

## 8. Fahrgemeinschaften
### Anforderungen
- Pro Begegnung mehrere Fahrgemeinschaften möglich
- Fahrer definiert Sitzplätze
- Beitritt bis Kapazität erreicht
- Treffpunkt & Zeit optional

## 9. Essen & Spesen
### Essen
- Spieler geben an: Ja / Nein
- Status sichtbar für Captain

### Spesen
- Captain lädt Beleg hoch
- Gesamtbetrag wird gleichmässig geteilt
- Nur bestätigte Esser werden berücksichtigt
- Zahlungsstatus manuell bestätigbar

## 10. Benachrichtigungen
### Trigger
- Neue Begegnung
- Ersatzanfrage
- Nachrücken in Aufstellung
- Neue Spesen

## 11. Nicht-funktionale Anforderungen
- Mobile First
- Offline-lesbar (letzter Stand)
- Datenschutzkonform (CH/EU)
- Keine Änderungen an bestehender Supabase-Website-Struktur

## 12. Offene Punkte (später)
- Doppel-Aufstellung
- Statistiken
- Swiss Tennis Integration
