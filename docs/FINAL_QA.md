# Final QA — Lineup
> Tester: _______________  
> Datum: 2026-02-16

---

## Invite/Join Stability

### Testplan

| # | Schritt | Details |
|---|---|---|
| 1 | Debug Build starten | `flutter run` auf echtem Gerät |
| 2 | Invite Link öffnen | `lineup://join?token=...` (Safari / AirDrop / Notes) |
| 3 | "Wie heisst du?" Sheet | Name eingeben → "Speichern" |
| 4 | Prüfen | Kein Red Screen, saubere Navigation zu Team |
| 5 | Team entfernen | In "Meine Teams" → Swipe → "Entfernen" |
| 6 | Erneut joinen | Gleichen Invite Link nochmals öffnen |
| 7 | Name eingeben → Speichern | Wieder im Sheet |
| 8 | Wiederholen | Schritte 5–7 insgesamt **10×** |

### Xcode Console: Achte auf diese Patterns

```
_dependents.isEmpty
_children.contains(child)
setState() called after dispose
A ValueNotifier was used after being disposed
FlutterError
PlatformDispatcher.onError
```

---

### iOS Ergebnis

- **Gerät:** ___________________________ (z.B. iPhone 15 Pro, iOS 17.4)
- **Build:** Debug / Release
- **Ergebnis:** ☐ PASS  ☐ FAIL

| Durchgang | Ergebnis | Anmerkung |
|-----------|----------|-----------|
| 1         |          |           |
| 2         |          |           |
| 3         |          |           |
| 4         |          |           |
| 5         |          |           |
| 6         |          |           |
| 7         |          |           |
| 8         |          |           |
| 9         |          |           |
| 10        |          |           |

**Console Exceptions:**
```
(Stacktrace hier einfügen falls FAIL)
```

---

### Android Ergebnis

- **Gerät:** ___________________________ (z.B. Pixel 7, Android 14)
- **Build:** Debug / Release
- **Ergebnis:** ☐ PASS  ☐ FAIL

| Durchgang | Ergebnis | Anmerkung |
|-----------|----------|-----------|
| 1         |          |           |
| 2         |          |           |
| 3         |          |           |

**Console Exceptions:**
```
(Stacktrace hier einfügen falls FAIL)
```

---

## Weitere Checks (optional, bei Gelegenheit)

- [ ] AuthScreen aus "Konto erforderlich" → Back/Close funktioniert
- [ ] Android System-Back auf AuthScreen → zurück zu Teams
- [ ] "Wie heisst du?" Sheet ist weiß/hell (Light Design)
- [ ] Push Notification erscheint (wenn Edge Functions deployed)
- [ ] Email Verification Pending Screen → Resend Button funktioniert
