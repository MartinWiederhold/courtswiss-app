// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get tabTeams => 'Teams';

  @override
  String get tabGames => 'Spiele';

  @override
  String get tabProfile => 'Profil';

  @override
  String get profileTitle => 'Profil';

  @override
  String get anonymousPlayer => 'Anonymer Spieler';

  @override
  String get notLoggedIn => 'Nicht eingeloggt';

  @override
  String get loggedIn => 'Eingeloggt';

  @override
  String get pushNotifications => 'Push-Benachrichtigungen';

  @override
  String get pushToggleSubtitle => 'Alle Push-Nachrichten ein/aus';

  @override
  String get individualNotifications => 'Einzelne Benachrichtigungen';

  @override
  String get pushInfoBanner =>
      'Push-Nachrichten werden in Kürze aktiviert. Deine Einstellungen werden bereits gespeichert.';

  @override
  String get createAccountHint =>
      'Erstelle ein Konto, um eigene Teams zu erstellen und dein Profil zu sichern.';

  @override
  String get registerLogin => 'Registrieren / Anmelden';

  @override
  String get logout => 'Abmelden';

  @override
  String get appVersion => 'Lineup · v1.0.0';

  @override
  String get prefsLoadError => 'Einstellungen konnten nicht geladen werden.';

  @override
  String get prefsSaveError =>
      'Einstellungen konnten nicht gespeichert werden.';

  @override
  String get languageTitle => 'Sprache';

  @override
  String get german => 'Deutsch';

  @override
  String get english => 'English';

  @override
  String get myTeams => 'Meine Teams';

  @override
  String get notifications => 'Benachrichtigungen';

  @override
  String get howItWorks => 'So funktioniert’s';

  @override
  String get guideStep1 => 'Erstelle dein Team über das + unten rechts.';

  @override
  String get guideStep2 =>
      'Füge Spieler hinzu – mit Name und optionalem Ranking.';

  @override
  String get guideStep3 => 'Teile den Einladungslink per WhatsApp.';

  @override
  String get guideStep4 =>
      'Spieler öffnen den Link und ordnen sich ihrem Namen zu.';

  @override
  String get guideStep5 => 'Du siehst als Captain, wer bereits verbunden ist.';

  @override
  String get guideStep6 =>
      'Erstelle Spiele – die Aufstellung wird nach Ranking sortiert.';

  @override
  String welcomeTitle(String appName) {
    return 'Willkommen bei $appName';
  }

  @override
  String get welcomeSubtitle =>
      'Erstelle dein erstes Team und lade Spieler ein.';

  @override
  String get understood => 'Verstanden';

  @override
  String get accountRequired => 'Konto erforderlich';

  @override
  String get accountRequiredBody =>
      'Um eigene Teams zu erstellen, benötigst du ein Konto. Registriere dich oder melde dich an.';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get deleteTeamTitle => 'Team löschen?';

  @override
  String deleteTeamBody(String teamName) {
    return 'Möchtest du „$teamName“ endgültig löschen? Das kann nicht rückgängig gemacht werden.';
  }

  @override
  String get delete => 'Löschen';

  @override
  String teamDeleted(String teamName) {
    return 'Team „$teamName“ gelöscht';
  }

  @override
  String get teamDeleteError => 'Team konnte nicht gelöscht werden.';

  @override
  String get removeTeamTitle => 'Team entfernen?';

  @override
  String removeTeamBody(String teamName) {
    return 'Du entfernst „$teamName“ nur aus deiner Liste. Das Team bleibt für den Captain und andere Mitglieder bestehen.';
  }

  @override
  String get remove => 'Entfernen';

  @override
  String teamRemoved(String teamName) {
    return 'Team „$teamName“ entfernt';
  }

  @override
  String get teamRemoveError => 'Team konnte nicht entfernt werden.';

  @override
  String get ownTeams => 'Eigene Teams';

  @override
  String get sharedTeams => 'Geteilte Teams';

  @override
  String get connectionError => 'Verbindungsproblem';

  @override
  String get dataLoadError => 'Daten konnten nicht geladen werden.';

  @override
  String get tryAgain => 'Nochmal versuchen';

  @override
  String season(String year) {
    return 'Saison $year';
  }

  @override
  String get gamesTitle => 'Spiele';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get noGamesYet => 'Noch keine Spiele';

  @override
  String get noGamesSubtitle => 'Erstelle dein erstes Spiel in einem Team.';

  @override
  String get home => 'Heim';

  @override
  String get away => 'Auswärts';

  @override
  String get authWelcome => 'Willkommen';

  @override
  String get authSubtitle => 'Dein Team. Deine Matches.';

  @override
  String get login => 'Anmelden';

  @override
  String get register => 'Registrieren';

  @override
  String get email => 'E-Mail';

  @override
  String get password => 'Passwort';

  @override
  String get forgotPassword => 'Passwort vergessen?';

  @override
  String get confirmPassword => 'Passwort bestätigen';

  @override
  String get passwordHint => 'Mind. 8 Zeichen mit mind. 1 Zahl';

  @override
  String get passwordMinLength => 'Mindestens 8 Zeichen';

  @override
  String get passwordNeedsNumber => 'Mind. 1 Zahl erforderlich';

  @override
  String get invalidEmail => 'Bitte eine gültige E-Mail eingeben.';

  @override
  String get enterPassword => 'Bitte Passwort eingeben.';

  @override
  String get passwordsMismatch => 'Passwörter stimmen nicht überein.';

  @override
  String get loginFailed =>
      'Anmeldung fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get registerFailed =>
      'Registrierung fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get invalidCredentials => 'E-Mail oder Passwort ungültig.';

  @override
  String get emailNotConfirmed =>
      'E-Mail noch nicht bestätigt. Bitte prüfe dein Postfach.';

  @override
  String get emailAlreadyRegistered =>
      'Diese E-Mail ist bereits registriert. Bitte melde dich an.';

  @override
  String get rateLimited => 'Zu viele Versuche. Bitte warte kurz.';

  @override
  String errorPrefix(String message) {
    return 'Fehler: $message';
  }

  @override
  String get verificationPendingTitle => 'E-Mail prüfen';

  @override
  String get verificationPendingBody =>
      'Wenn ein Konto mit dieser E-Mail existiert, haben wir dir eine Bestätigungs-E-Mail geschickt. Bitte prüfe Posteingang und Spam.';

  @override
  String get resendConfirmationEmail => 'Bestätigungs-Mail erneut senden';

  @override
  String get resendEmailSuccess => 'E-Mail wurde gesendet (sofern möglich).';

  @override
  String get resendEmailRateLimit =>
      'Bitte warte ein paar Minuten und versuche es erneut.';

  @override
  String get alreadyHaveAccountLogin => 'Du hast bereits ein Konto? Anmelden';

  @override
  String get save => 'Speichern';

  @override
  String get matchDetails => 'Spieldetails';

  @override
  String get opponent => 'Gegner *';

  @override
  String get opponentHint => 'z.B. TC Zürich';

  @override
  String get pleaseComplete => 'Bitte ausfüllen';

  @override
  String get dateAndTime => 'Datum & Zeit';

  @override
  String get chooseDate => 'Datum wählen';

  @override
  String get chooseTime => 'Uhrzeit wählen';

  @override
  String get homeGame => 'Heimspiel';

  @override
  String get awayGame => 'Auswärtsspiel';

  @override
  String get details => 'Details';

  @override
  String get location => 'Ort';

  @override
  String get locationHint => 'z.B. Tennisclub Bern, Platz 3';

  @override
  String get noteOptional => 'Notiz (optional)';

  @override
  String get noteHint => 'z.B. Treffpunkt 09:30';

  @override
  String get chooseDateAndTime => 'Bitte Datum und Uhrzeit wählen';

  @override
  String get editMatch => 'Spiel bearbeiten';

  @override
  String get addMatch => 'Spiel hinzufügen';

  @override
  String get saveChanges => 'Änderungen speichern';

  @override
  String get createMatch => 'Spiel erstellen';

  @override
  String get matchUpdated => 'Spiel aktualisiert';

  @override
  String get matchCreated => 'Spiel erstellt';

  @override
  String get matchCreateError =>
      'Spiel konnte nicht erstellt werden. Bitte versuche es erneut.';

  @override
  String get lineupPublished => 'Aufstellung veröffentlicht';

  @override
  String get replacementPromoted => 'Ersatz nachgerückt';

  @override
  String get noReserveAvailable => 'Kein Ersatz verfügbar';

  @override
  String get accountSectionTitle => 'Konto';

  @override
  String get deleteAccount => 'Konto löschen';

  @override
  String get deleteAccountTitle => 'Konto löschen?';

  @override
  String get deleteAccountBody =>
      'Dein Konto und alle damit verbundenen Daten werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String typeToConfirm(String confirmWord) {
    return 'Tippe „$confirmWord“ zur Bestätigung';
  }

  @override
  String get confirmWordDelete => 'LÖSCHEN';

  @override
  String get deleting => 'Wird gelöscht…';

  @override
  String get accountDeleted => 'Konto gelöscht';

  @override
  String get accountDeleteError =>
      'Konto konnte nicht gelöscht werden. Bitte versuche es erneut.';

  @override
  String get teamDetailTabOverview => 'Übersicht';

  @override
  String get teamDetailTabTeam => 'Team';

  @override
  String get teamDetailTabMatches => 'Spiele';

  @override
  String get teamInfoBadge => 'Team Info';

  @override
  String get teamInfoTeam => 'Team';

  @override
  String get teamInfoClub => 'Club';

  @override
  String get teamInfoLeague => 'Liga';

  @override
  String get teamInfoSeason => 'Saison';

  @override
  String get teamInfoCaptain => 'Kapitän';

  @override
  String get nextMatch => 'Nächstes Spiel';

  @override
  String get playersLabel => 'Spieler';

  @override
  String get connectedLabel => 'Verbunden';

  @override
  String get captainPlaysTitle => 'Ich spiele selbst';

  @override
  String get captainPlaysSubtitle =>
      'Aktiviere dies, wenn du als Captain auch spielst und in der Aufstellung erscheinen möchtest.';

  @override
  String get inviteLinkTitle => 'Einladungslink';

  @override
  String get inviteLinkDescription =>
      'Teile den Einladungslink, damit sich Spieler dem Team anschliessen können.';

  @override
  String get shareLink => 'Link teilen';

  @override
  String get inviteLinkCreated => 'Einladungslink erstellt';

  @override
  String get inviteLinkError => 'Einladungslink konnte nicht erstellt werden.';

  @override
  String get shareInviteTooltip => 'Einladungslink teilen';

  @override
  String get shareSubject => 'Lineup Team-Einladung';

  @override
  String teamSectionCount(String count) {
    return 'Team ($count)';
  }

  @override
  String connectedPlayersTitle(String count) {
    return 'Verbundene Spieler ($count)';
  }

  @override
  String get addPlayer => 'Spieler hinzufügen';

  @override
  String get firstName => 'Vorname *';

  @override
  String get firstNameHint => 'Max';

  @override
  String get lastName => 'Nachname *';

  @override
  String get lastNameHint => 'Muster';

  @override
  String get enterFirstAndLastName => 'Bitte Vor- und Nachname eingeben.';

  @override
  String get selectRanking => 'Bitte ein Ranking auswählen.';

  @override
  String get genericError =>
      'Etwas ist schiefgelaufen. Bitte versuche es erneut.';

  @override
  String get addButton => 'Hinzufügen';

  @override
  String get whatsYourName => 'Wie heisst du?';

  @override
  String get nicknamePrompt =>
      'Bitte gib deinen Namen ein, damit dein Team dich erkennt.';

  @override
  String get yourTeamName => 'Dein Name im Team';

  @override
  String get nicknameHint => 'z.B. Max, Sandro, Martin W.';

  @override
  String get minTwoChars => 'Mindestens 2 Zeichen';

  @override
  String get nicknameSaveError => 'Spieler konnte nicht hinzugefügt werden.';

  @override
  String get nameSaved => 'Name gespeichert';

  @override
  String get changeName => 'Name ändern';

  @override
  String get nameUpdated => 'Name aktualisiert';

  @override
  String get nameSaveError => 'Name konnte nicht gespeichert werden.';

  @override
  String get changeSaveError => 'Änderung konnte nicht gespeichert werden.';

  @override
  String get noPlayersYet => 'Noch keine Spieler';

  @override
  String get noPlayersEmptyBody =>
      'Noch keine Spieler vorhanden.\nFüge Spieler mit Name und Ranking hinzu.';

  @override
  String get shareInviteSubtitle =>
      'Teile den Einladungslink, damit sich Spieler zuordnen können.';

  @override
  String get noMatchesTeamSubtitle =>
      'Erstelle ein Spiel, damit dein Team reagieren kann.';

  @override
  String get chipOpen => 'Offen';

  @override
  String get chipAssigned => 'Zugeordnet';

  @override
  String get chipYou => 'Du';

  @override
  String get chipConnected => 'Verbunden';

  @override
  String get chipCaptain => 'Captain';

  @override
  String get chipCaptainPlaying => 'Captain (spielend)';

  @override
  String get chipPlayer => 'Spieler';

  @override
  String get changeAvatarTooltip => 'Profilbild ändern';

  @override
  String get claimSlotTooltip => 'Spieler-Slot zuordnen';

  @override
  String get changeNameTooltip => 'Name ändern';

  @override
  String get actionError => 'Aktion konnte nicht ausgeführt werden.';

  @override
  String get avatarUpdated => 'Profilbild aktualisiert';

  @override
  String get avatarUploadError => 'Bild konnte nicht hochgeladen werden.';

  @override
  String get storageSetupRequired => 'Storage Setup erforderlich';

  @override
  String get storageSetupBody =>
      'Der Storage-Bucket „profile-photos“ wurde noch nicht angelegt.\nBitte folge diesen Schritten:';

  @override
  String get storageStep1 => 'Supabase Dashboard → Storage → „New bucket“';

  @override
  String get storageStep2 => 'Name exakt: profile-photos';

  @override
  String get storageStep3 => 'Public: OFF (private)';

  @override
  String get storageStep4 => 'SQL Editor → untenstehende Policies ausführen';

  @override
  String get sqlCopied => 'SQL in Zwischenablage kopiert';

  @override
  String get copySql => 'SQL kopieren';

  @override
  String get closeButton => 'Schliessen';

  @override
  String get notificationsTooltip => 'Benachrichtigungen';

  @override
  String get removePlayer => 'Entfernen';

  @override
  String get matchTabOverview => 'Übersicht';

  @override
  String get matchTabLineup => 'Aufstellung';

  @override
  String get matchTabMore => 'Mehr';

  @override
  String get editLabel => 'Bearbeiten';

  @override
  String matchConfirmedProgress(String yes, String total) {
    return '$yes von $total zugesagt';
  }

  @override
  String get myAvailability => 'Meine Verfügbarkeit';

  @override
  String get availYes => 'Zugesagt';

  @override
  String get availNo => 'Abgesagt';

  @override
  String get availMaybe => 'Unsicher';

  @override
  String get availNoResponse => 'Keine Antwort';

  @override
  String get availabilitiesTitle => 'Verfügbarkeiten';

  @override
  String respondedProgress(String responded, String total) {
    return '$responded von $total haben geantwortet';
  }

  @override
  String get playerAvailabilities => 'Verfügbarkeiten der Spieler';

  @override
  String get subRequestSection => 'Ersatz';

  @override
  String get noSubRequests =>
      'Keine Ersatzanfragen vorhanden. Bei Absagen kannst du hier Ersatz anfragen.';

  @override
  String get generateLineupTitle => 'Aufstellung generieren';

  @override
  String get generateButton => 'Generieren';

  @override
  String get lineupGenerateDescription =>
      'Die Aufstellung wird anhand des Rankings und der Verfügbarkeiten erstellt.\nDu kannst danach manuell tauschen.\n\nEine bestehende Aufstellung wird überschrieben.';

  @override
  String get starterLabel => 'Starter';

  @override
  String get reserveLabel => 'Ersatz';

  @override
  String get includeMaybeTitle => 'Unsichere berücksichtigen';

  @override
  String get includeMaybeSubtitle =>
      'Spieler mit „Unsicher“ werden ergänzend aufgestellt.';

  @override
  String lineupCreatedToast(String starters, String reserves) {
    return 'Aufstellung erstellt: $starters Starter, $reserves Ersatz';
  }

  @override
  String get lineupTitle => 'Aufstellung';

  @override
  String get lineupStatusDraft => 'Entwurf';

  @override
  String get lineupStatusPublished => 'Veröffentlicht';

  @override
  String get allSlotsOccupied => 'Alle Plätze besetzt';

  @override
  String get slotsFreeSingle => '1 Platz frei';

  @override
  String slotsFree(String count) {
    return '$count Plätze frei';
  }

  @override
  String get regenerateButton => 'Neu generieren';

  @override
  String get noLineupYet => 'Noch keine Aufstellung vorhanden.';

  @override
  String get noLineupYetAdmin =>
      'Noch keine Aufstellung vorhanden.\nTippe auf „Generieren“, um eine zu erstellen.';

  @override
  String get captainCreatingLineup =>
      'Captain erstellt gerade die Aufstellung …';

  @override
  String get subChainActive =>
      'Ersatzkette aktiv: Bei Absage rückt der nächste Ersatz automatisch nach.';

  @override
  String starterCountHeader(String count) {
    return 'Starter ($count)';
  }

  @override
  String reserveCountHeader(String count) {
    return 'Ersatz ($count)';
  }

  @override
  String get sendLineupToTeam => 'Info an Team senden';

  @override
  String get lineupPublishedBanner =>
      'Aufstellung veröffentlicht. Absagen lösen automatisches Nachrücken aus.';

  @override
  String get youStarter => 'Du · Starter';

  @override
  String get youReserve => 'Du · Ersatz';

  @override
  String get publishLineupTitle => 'Aufstellung veröffentlichen?';

  @override
  String get publishSendButton => 'Senden';

  @override
  String get publishLineupBody =>
      'Alle Team-Mitglieder werden über die Aufstellung informiert (In-App + Push).';

  @override
  String get publishLineupConfirm =>
      'Möchtest du die Aufstellung jetzt senden?';

  @override
  String lineupPublishedToast(String recipients) {
    return 'Aufstellung veröffentlicht – $recipients Benachrichtigungen gesendet';
  }

  @override
  String get violationSingle => '⚠️ 1 Regelverstoss erkannt';

  @override
  String violationMultiple(String count) {
    return '⚠️ $count Regelverstösse erkannt';
  }

  @override
  String violationMore(String count) {
    return '… und $count weitere';
  }

  @override
  String get publishAnyway => 'Veröffentlichung trotzdem möglich.';

  @override
  String get lineupPublishedNoReorder =>
      'Aufstellung ist veröffentlicht – Reihenfolge kann nicht mehr geändert werden.';

  @override
  String get lineupBeingGenerated => 'Aufstellung wird generiert …';

  @override
  String get lineupBeingPublished => 'Aufstellung wird veröffentlicht …';

  @override
  String get reorderNotPossible =>
      'Reihenfolge ändern ist momentan nicht möglich.';

  @override
  String get deleteMatchTitle => 'Spiel löschen?';

  @override
  String deleteMatchBody(String opponent) {
    return 'Möchtest du das Spiel gegen „$opponent“ wirklich löschen?\n\nAlle Verfügbarkeiten und Aufstellungen gehen verloren.';
  }

  @override
  String get matchDeleted => 'Spiel gelöscht';

  @override
  String subRequestSentToast(String name) {
    return 'Ersatzanfrage an $name gesendet';
  }

  @override
  String get noSubAvailable => 'Kein verfügbarer Ersatzspieler gefunden.';

  @override
  String get subRequestAcceptedToast => 'Ersatzanfrage angenommen';

  @override
  String get subRequestDeclinedToast => 'Ersatzanfrage abgelehnt';

  @override
  String get somethingWentWrong => 'Etwas ist schiefgelaufen.';

  @override
  String get subRequestsTitle => 'Ersatzanfragen';

  @override
  String pendingCountChip(String count) {
    return '$count ausstehend';
  }

  @override
  String get pendingRequestsLabel => 'Ausstehende Anfragen';

  @override
  String get youWereAsked => 'Du wurdest angefragt:';

  @override
  String subForPlayer(String name) {
    return 'Ersatz für $name';
  }

  @override
  String get canYouStepIn => 'Kannst du einspringen?';

  @override
  String get timeExpired => 'Zeit abgelaufen';

  @override
  String get acceptTooltip => 'Annehmen';

  @override
  String get declineTooltip => 'Ablehnen';

  @override
  String get requestHistory => 'Anfragen-Verlauf:';

  @override
  String subForPlayerHistory(String subName, String originalName) {
    return '$subName für $originalName';
  }

  @override
  String get chipWaiting => 'Wartet auf Antwort';

  @override
  String get chipAccepted => 'Angenommen';

  @override
  String get chipDeclined => 'Abgelehnt';

  @override
  String get subButton => 'Ersatz';

  @override
  String get sectionRides => 'Fahrten';

  @override
  String get carpoolsTitle => 'Fahrgemeinschaften';

  @override
  String get iDriveButton => 'Ich fahre';

  @override
  String get noCarpoolsYet => 'Noch keine Fahrgemeinschaften vorhanden.';

  @override
  String get noCarpoolsHint =>
      'Noch keine Fahrgemeinschaften. Biete eine Mitfahrgelegenheit an.';

  @override
  String get youSuffix => '(du)';

  @override
  String get joinRideButton => 'Mitfahren';

  @override
  String get leaveRideButton => 'Aussteigen';

  @override
  String get joinedRideToast => 'Du fährst mit';

  @override
  String get joinRideError => 'Mitfahren konnte nicht gespeichert werden.';

  @override
  String get leftRideToast => 'Ausgestiegen';

  @override
  String get leaveRideError => 'Aussteigen konnte nicht gespeichert werden.';

  @override
  String get deleteCarpoolTitle => 'Fahrgemeinschaft löschen?';

  @override
  String get deleteCarpoolBody => 'Alle Mitfahrer werden entfernt.';

  @override
  String get editCarpoolTitle => 'Fahrgemeinschaft bearbeiten';

  @override
  String get seatsQuestion => 'Wie viele Plätze bietest du an?';

  @override
  String get departureLocationLabel => 'Abfahrtsort';

  @override
  String get departureLocationHint => 'z.B. Bahnhof Bern';

  @override
  String departureTimeWithValue(String time) {
    return 'Abfahrt: $time';
  }

  @override
  String get departureTimeOptional => 'Abfahrtszeit (optional)';

  @override
  String get changeTooltip => 'Ändern';

  @override
  String get setTooltip => 'Setzen';

  @override
  String get removeTooltipLabel => 'Entfernen';

  @override
  String get carpoolNoteHint => 'z.B. Treffpunkt Parkplatz';

  @override
  String get carpoolSavedToast => 'Fahrgemeinschaft gespeichert';

  @override
  String get carpoolCreatedReloadToast =>
      'Fahrgemeinschaft erstellt. Bitte lade die Seite neu.';

  @override
  String departAtFormat(String date, String time) {
    return '$date um $time';
  }

  @override
  String get sectionDinner => 'Essen';

  @override
  String answeredOfTotal(String answered, String total) {
    return '$answered von $total';
  }

  @override
  String get yourRsvp => 'Deine Zusage';

  @override
  String get dinnerYes => 'Ja';

  @override
  String get dinnerNo => 'Nein';

  @override
  String get dinnerMaybe => 'Unsicher';

  @override
  String get dinnerNoteHint => 'Notiz (z.B. „komme später“)';

  @override
  String get dinnerSaveError =>
      'Speichern nicht möglich. Bitte versuche es erneut.';

  @override
  String get participantsTitle => 'Teilnehmer';

  @override
  String get sectionExpenses => 'Spesen';

  @override
  String get expenseTotal => 'Total';

  @override
  String perPersonLabel(String count) {
    return 'Pro Kopf ($count Pers.)';
  }

  @override
  String get paidLabel => 'Bezahlt';

  @override
  String get firstConfirmDinner =>
      'Zuerst unter „Essen“ zusagen, bevor Spesen erfasst werden können.';

  @override
  String get addExpenseButton => 'Ausgabe hinzufügen';

  @override
  String get noExpensesYet =>
      'Noch keine Spesen erfasst. Lege eine neue Ausgabe an.';

  @override
  String get noExpensesPossible =>
      'Noch keine Spesen möglich. Zuerst unter „Essen“ zusagen.';

  @override
  String paidByLabel(String name) {
    return 'Bezahlt von $name';
  }

  @override
  String perPersonAmountLabel(String amount) {
    return '$amount/Pers.';
  }

  @override
  String paidOfShareCount(String paid, String total) {
    return '$paid/$total bezahlt';
  }

  @override
  String get sharePaid => 'Bezahlt';

  @override
  String get shareOpen => 'Offen';

  @override
  String get deleteExpenseTooltip => 'Ausgabe löschen';

  @override
  String get markedAsPaid => 'Als bezahlt markiert';

  @override
  String get markedAsOpen => 'Als offen markiert';

  @override
  String get expenseTitleField => 'Titel *';

  @override
  String get expenseTitleHint => 'z.B. Pizza, Getränke';

  @override
  String get expenseAmountField => 'Betrag (CHF) *';

  @override
  String get expenseAmountHint => 'z.B. 45.50';

  @override
  String get currencyPrefix => 'CHF ';

  @override
  String get expenseNoteHint => 'z.B. Restaurant Adler';

  @override
  String expenseDistribution(String count) {
    return 'Wird gleichmässig auf alle $count Dinner-Teilnehmer (Ja) verteilt.';
  }

  @override
  String get enterTitleValidation => 'Bitte gib einen Titel ein.';

  @override
  String get enterAmountValidation => 'Bitte gib einen gültigen Betrag ein.';

  @override
  String expenseCreatedToast(String title, String amount) {
    return 'Ausgabe „$title“ (CHF $amount) erstellt';
  }

  @override
  String get deleteExpenseTitle => 'Ausgabe löschen?';

  @override
  String deleteExpenseBody(String title, String amount) {
    return '„$title“ ($amount) und alle Anteile werden gelöscht.';
  }

  @override
  String expenseDeletedToast(String title) {
    return 'Ausgabe „$title“ gelöscht';
  }

  @override
  String get roleCaptainSuffix => ' (Captain)';

  @override
  String get unknownPlayer => 'Unbekannt';

  @override
  String get lineupReorderHint => 'Halte ☰ und ziehe um Positionen zu tauschen';

  @override
  String get claimConfirmTitle => 'Spieler bestätigen';

  @override
  String get claimConfirmCta => 'Ja, das bin ich';

  @override
  String claimConfirmBody(String label) {
    return 'Bist du „$label“?';
  }

  @override
  String claimWelcomeToast(String name) {
    return 'Willkommen, $name!';
  }

  @override
  String get claimWhoAreYou => 'Wer bist du?';

  @override
  String get commonSkip => 'Überspringen';

  @override
  String get claimPickName =>
      'Wähle deinen Namen aus der Liste,\ndamit das Team dich zuordnen kann.';

  @override
  String get claimSearchHint => 'Name suchen…';

  @override
  String get claimNoSlotTitle => 'Kein freier Platz';

  @override
  String get claimNoSlotBody =>
      'Dein Captain hat noch keine Spieler angelegt\noder alle Plätze sind bereits vergeben.';

  @override
  String get notifLoadError =>
      'Benachrichtigungen konnten nicht geladen werden.';

  @override
  String get matchLoadError => 'Spiel konnte nicht geladen werden.';

  @override
  String notifTitleWithCount(String count) {
    return 'Benachrichtigungen ($count)';
  }

  @override
  String get markAllRead => 'Alle gelesen';

  @override
  String get allReadTitle => 'Alles gelesen';

  @override
  String get allReadSubtitle =>
      'Neue Benachrichtigungen erscheinen automatisch hier.';

  @override
  String get timeJustNow => 'gerade eben';

  @override
  String timeMinutesAgo(String minutes) {
    return 'vor $minutes Min.';
  }

  @override
  String timeHoursAgo(String hours) {
    return 'vor $hours Std.';
  }

  @override
  String timeDaysAgo(String days) {
    return 'vor $days Tagen';
  }

  @override
  String get forgotPasswordAppBar => 'Passwort vergessen';

  @override
  String get resetPasswordTitle => 'Passwort zurücksetzen';

  @override
  String get resetPasswordInstructions =>
      'Gib deine E-Mail-Adresse ein und wir senden dir einen Link zum Zurücksetzen.';

  @override
  String get emailSentTitle => 'E-Mail gesendet!';

  @override
  String get resetPasswordSentBody =>
      'Prüfe dein Postfach und klicke auf den Link, um ein neues Passwort zu setzen.';

  @override
  String get backToSignIn => 'Zurück zur Anmeldung';

  @override
  String get sendLinkButton => 'Link senden';

  @override
  String get emailSendError => 'E-Mail konnte nicht gesendet werden.';

  @override
  String get sportSelectionTitle => 'Sportart wählen';

  @override
  String get sportSelectionSubtitle => 'Welche Sportart spielt dein Team?';

  @override
  String get eventsLoadError => 'Events konnten nicht geladen werden.';

  @override
  String get matchUnavailableDeleted =>
      'Match nicht verfügbar (gelöscht oder archiviert).';

  @override
  String get matchUnavailable => 'Match nicht verfügbar.';

  @override
  String get noNewEvents => 'Keine neuen Events';

  @override
  String get noNewEventsSubtitle =>
      'Sobald es Neuigkeiten gibt, siehst du sie hier.';

  @override
  String get teamFilterLabel => 'Team-Filter';

  @override
  String get allTeams => 'Alle Teams';

  @override
  String get createTeamTitle => 'Team erstellen';

  @override
  String get teamNameLabel => 'Club Name / Team Name *';

  @override
  String get teamNameHint => 'z.B. TC Winterthur 1';

  @override
  String get leagueLabel => 'Liga (optional)';

  @override
  String get leagueHint => 'z.B. 3. Liga Herren';

  @override
  String get seasonYearLabel => 'Saison Jahr';

  @override
  String get captainNameRequired => 'Dein Name im Team *';

  @override
  String get captainNamePrompt => 'Dein Name, damit dein Team dich erkennt.';

  @override
  String get createTeamPlaysSelfSubtitle =>
      'Aktiviere dies, wenn du als Captain auch spielst.';

  @override
  String get createButton => 'Erstellen';

  @override
  String get teamCreatedToast => 'Team erstellt';

  @override
  String get teamCreateError =>
      'Team konnte nicht erstellt werden. Bitte versuche es erneut.';

  @override
  String get enterTeamName => 'Bitte Team Name eingeben.';

  @override
  String get enterCaptainName =>
      'Bitte deinen Namen eingeben (min. 2 Zeichen).';

  @override
  String get invalidSeasonYear => 'Bitte gültiges Saison-Jahr eingeben.';

  @override
  String get selectRankingError => 'Bitte Ranking auswählen.';

  @override
  String get countryLabel => 'Land *';

  @override
  String get rankingLabelRequired => 'Ranking *';

  @override
  String get rankingAvailableSection => 'Verfügbar';

  @override
  String get dropdownHint => 'Bitte auswählen';

  @override
  String get notifTitleLineup => 'Aufstellung';

  @override
  String get notifTitleSubRequest => 'Ersatzanfrage';

  @override
  String get notifTitlePromotion => 'Nachrücker';

  @override
  String get notifTitleAutoPromotion => 'Auto-Nachrücken';

  @override
  String get notifTitleLineupGenerated => 'Aufstellung erstellt';

  @override
  String get notifTitleConfirmation => 'Bestätigung';

  @override
  String get notifTitleWarning => 'Achtung';

  @override
  String get notifTitlePromoted => 'Beförderung';

  @override
  String get notifBodyLineupOnline =>
      'Die Aufstellung ist online. Schau sie dir an!';

  @override
  String notifBodySelectedAs(String role, String position) {
    return 'Du wurdest als $role (Pos. $position) aufgestellt';
  }

  @override
  String notifBodyReserveConfirm(String position) {
    return 'Du bist Ersatz $position. Bitte bestätige.';
  }

  @override
  String notifBodyPromotedToStarter(String position) {
    return 'Du wurdest zum Starter (Pos. $position) befördert 🎉';
  }

  @override
  String get notifBodyAutoPromoted =>
      'Du bist als Ersatz nachgerückt und spielst nun mit 🎉';

  @override
  String notifBodyAutoPromotionCaptain(String inName, String outName) {
    return 'Auto-Nachrücken: $inName ersetzt $outName';
  }

  @override
  String notifBodyNoReserve(String absent) {
    return '$absent hat abgesagt – kein Ersatz verfügbar!';
  }

  @override
  String notifBodyLineupCreated(String starters, String reserves) {
    return 'Aufstellung erstellt: $starters Starter, $reserves Ersatz';
  }

  @override
  String get notifBodyPlayerConfirmed => 'Ein Spieler hat bestätigt';

  @override
  String get notifBodyNoReservesLeft => 'Keine Ersatzspieler mehr verfügbar!';

  @override
  String notifBodyPromotedToPos(String position) {
    return 'Du wurdest zum Starter befördert (Pos. $position) 🎉';
  }

  @override
  String get notifBodyRosterChanged => 'Die Aufstellung wurde geändert';

  @override
  String get notifBodyNeedsResponse => 'Bitte bestätige deine Aufstellung';

  @override
  String eventBodyReplaced(String inName, String outName) {
    return '$inName ersetzt $outName';
  }
}
