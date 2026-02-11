# User Stories & Acceptance Criteria – CourtSwiss (MVP)

## Epic 1: Auth & Profil

### US-1.1: Registrierung & Login
**Als Spieler:in**  
möchte ich mich per Magic Link oder Passwort anmelden,  
damit ich ohne komplizierte Registrierung Zugriff auf mein Team habe.

**Acceptance Criteria**
- Login via Supabase Auth
- Nach Login wird ein App-Profil angelegt (falls nicht vorhanden)
- Nutzer bleibt eingeloggt

---

## Epic 2: Team-Management

### US-2.1: Team erstellen (Captain)
**Als Captain**  
möchte ich ein Team erstellen,  
damit ich Interclub-Begegnungen planen kann.

**Acceptance Criteria**
- Teamname, Saison und Kategorie sind Pflichtfelder
- Captain wird automatisch als Teammitglied gesetzt

### US-2.2: Spieler zum Team einladen
**Als Captain**  
möchte ich Spieler per Einladungslink hinzufügen,  
damit sie meinem Team beitreten können.

**Acceptance Criteria**
- Einladungslink ist eindeutig
- Nur eingeladene Nutzer können dem Team beitreten
- Spieler erscheinen in der Teamliste

---

## Epic 3: Begegnungen (Fixtures)

### US-3.1: Begegnung erstellen
**Als Captain**  
möchte ich eine Begegnung mit Gegner, Datum und Ort anlegen,  
damit das Team planen kann.

**Acceptance Criteria**
- Begegnung gehört zu genau einem Team
- Begegnung erscheint in der Teamübersicht

---

## Epic 4: Verfügbarkeit

### US-4.1: Verfügbarkeit angeben
**Als Spieler:in**  
möchte ich angeben, ob ich Zeit habe,  
damit der Captain planen kann.

**Acceptance Criteria**
- Status: Ja / Nein / Vielleicht
- Änderung jederzeit möglich
- Captain sieht alle Antworten

---

## Epic 5: Aufstellung

### US-5.1: Automatische Aufstellung
**Als Captain**  
möchte ich automatisch eine Aufstellung generieren,  
damit ich Zeit spare.

**Acceptance Criteria**
- Sortierung nach Klassierung
- Richtige Anzahl Einzel
- Ersatzspieler werden automatisch gesetzt

### US-5.2: Manuelle Anpassung
**Als Captain**  
möchte ich die Aufstellung manuell anpassen,  
damit ich flexibel bleibe.

**Acceptance Criteria**
- Drag & Drop möglich
- Warnung bei Regelverstössen
- Änderungen werden gespeichert

---

## Epic 6: Ersatzspieler

### US-6.1: Ersatzanfrage erhalten
**Als Ersatzspieler**  
möchte ich eine Push-Benachrichtigung erhalten,  
damit ich kurzfristig einspringen kann.

**Acceptance Criteria**
- Push bei Anfrage
- Zusage oder Absage möglich
- Bei Absage wird nächster Ersatz angefragt

---

## Epic 7: Fahrgemeinschaften

### US-7.1: Fahrgemeinschaft erstellen
**Als Fahrer**  
möchte ich eine Fahrgemeinschaft erstellen,  
damit Mitspieler mitfahren können.

**Acceptance Criteria**
- Sitzplätze definierbar
- Treffpunkt und Zeit optional
- Status „voll" bei Erreichen der Kapazität

### US-7.2: Fahrgemeinschaft beitreten
**Als Spieler:in**  
möchte ich einer Fahrgemeinschaft beitreten,  
damit ich organisiert zum Spiel komme.

**Acceptance Criteria**
- Beitritt nur bei freien Plätzen
- Status sichtbar

---

## Epic 8: Essen & Spesen

### US-8.1: Essen zusagen
**Als Spieler:in**  
möchte ich angeben, ob ich nach dem Spiel zum Essen bleibe,  
damit der Captain planen kann.

**Acceptance Criteria**
- Ja / Nein auswählbar
- Status sichtbar für Captain

### US-8.2: Spesen erfassen
**Als Captain**  
möchte ich einen Beleg hochladen und Kosten aufteilen,  
damit alles transparent ist.

**Acceptance Criteria**
- Beleg-Upload möglich
- Kosten gleichmässig verteilt
- Zahlungsstatus pro Spieler sichtbar

---

## Epic 9: Benachrichtigungen

### US-9.1: Wichtige Events
**Als Nutzer:in**  
möchte ich über wichtige Ereignisse informiert werden,  
damit ich nichts verpasse.

**Acceptance Criteria**
- Push bei Ersatzanfrage
- Push bei Nachrücken
- Push bei neuer Spese
