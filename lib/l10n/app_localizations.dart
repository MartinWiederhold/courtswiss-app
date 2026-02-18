import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @tabTeams.
  ///
  /// In de, this message translates to:
  /// **'Teams'**
  String get tabTeams;

  /// No description provided for @tabGames.
  ///
  /// In de, this message translates to:
  /// **'Spiele'**
  String get tabGames;

  /// No description provided for @tabProfile.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get tabProfile;

  /// No description provided for @profileTitle.
  ///
  /// In de, this message translates to:
  /// **'Profil'**
  String get profileTitle;

  /// No description provided for @anonymousPlayer.
  ///
  /// In de, this message translates to:
  /// **'Anonymer Spieler'**
  String get anonymousPlayer;

  /// No description provided for @notLoggedIn.
  ///
  /// In de, this message translates to:
  /// **'Nicht eingeloggt'**
  String get notLoggedIn;

  /// No description provided for @loggedIn.
  ///
  /// In de, this message translates to:
  /// **'Eingeloggt'**
  String get loggedIn;

  /// No description provided for @pushNotifications.
  ///
  /// In de, this message translates to:
  /// **'Push-Benachrichtigungen'**
  String get pushNotifications;

  /// No description provided for @pushToggleSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Alle Push-Nachrichten ein/aus'**
  String get pushToggleSubtitle;

  /// No description provided for @individualNotifications.
  ///
  /// In de, this message translates to:
  /// **'Einzelne Benachrichtigungen'**
  String get individualNotifications;

  /// No description provided for @pushInfoBanner.
  ///
  /// In de, this message translates to:
  /// **'Push-Nachrichten werden in Kürze aktiviert. Deine Einstellungen werden bereits gespeichert.'**
  String get pushInfoBanner;

  /// No description provided for @createAccountHint.
  ///
  /// In de, this message translates to:
  /// **'Erstelle ein Konto, um eigene Teams zu erstellen und dein Profil zu sichern.'**
  String get createAccountHint;

  /// No description provided for @registerLogin.
  ///
  /// In de, this message translates to:
  /// **'Registrieren / Anmelden'**
  String get registerLogin;

  /// No description provided for @logout.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get logout;

  /// No description provided for @appVersion.
  ///
  /// In de, this message translates to:
  /// **'Lineup · v1.0.0'**
  String get appVersion;

  /// No description provided for @prefsLoadError.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen konnten nicht geladen werden.'**
  String get prefsLoadError;

  /// No description provided for @prefsSaveError.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen konnten nicht gespeichert werden.'**
  String get prefsSaveError;

  /// No description provided for @languageTitle.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get languageTitle;

  /// No description provided for @german.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get german;

  /// No description provided for @english.
  ///
  /// In de, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @myTeams.
  ///
  /// In de, this message translates to:
  /// **'Meine Teams'**
  String get myTeams;

  /// No description provided for @notifications.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen'**
  String get notifications;

  /// No description provided for @howItWorks.
  ///
  /// In de, this message translates to:
  /// **'So funktioniert’s'**
  String get howItWorks;

  /// No description provided for @guideStep1.
  ///
  /// In de, this message translates to:
  /// **'Erstelle dein Team über das + unten rechts.'**
  String get guideStep1;

  /// No description provided for @guideStep2.
  ///
  /// In de, this message translates to:
  /// **'Füge Spieler hinzu – mit Name und optionalem Ranking.'**
  String get guideStep2;

  /// No description provided for @guideStep3.
  ///
  /// In de, this message translates to:
  /// **'Teile den Einladungslink per WhatsApp.'**
  String get guideStep3;

  /// No description provided for @guideStep4.
  ///
  /// In de, this message translates to:
  /// **'Spieler öffnen den Link und ordnen sich ihrem Namen zu.'**
  String get guideStep4;

  /// No description provided for @guideStep5.
  ///
  /// In de, this message translates to:
  /// **'Du siehst als Captain, wer bereits verbunden ist.'**
  String get guideStep5;

  /// No description provided for @guideStep6.
  ///
  /// In de, this message translates to:
  /// **'Erstelle Spiele – die Aufstellung wird nach Ranking sortiert.'**
  String get guideStep6;

  /// No description provided for @welcomeTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen bei {appName}'**
  String welcomeTitle(String appName);

  /// No description provided for @welcomeSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Erstelle dein erstes Team und lade Spieler ein.'**
  String get welcomeSubtitle;

  /// No description provided for @understood.
  ///
  /// In de, this message translates to:
  /// **'Verstanden'**
  String get understood;

  /// No description provided for @accountRequired.
  ///
  /// In de, this message translates to:
  /// **'Konto erforderlich'**
  String get accountRequired;

  /// No description provided for @accountRequiredBody.
  ///
  /// In de, this message translates to:
  /// **'Um eigene Teams zu erstellen, benötigst du ein Konto. Registriere dich oder melde dich an.'**
  String get accountRequiredBody;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @deleteTeamTitle.
  ///
  /// In de, this message translates to:
  /// **'Team löschen?'**
  String get deleteTeamTitle;

  /// No description provided for @deleteTeamBody.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du „{teamName}“ endgültig löschen? Das kann nicht rückgängig gemacht werden.'**
  String deleteTeamBody(String teamName);

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @teamDeleted.
  ///
  /// In de, this message translates to:
  /// **'Team „{teamName}“ gelöscht'**
  String teamDeleted(String teamName);

  /// No description provided for @teamDeleteError.
  ///
  /// In de, this message translates to:
  /// **'Team konnte nicht gelöscht werden.'**
  String get teamDeleteError;

  /// No description provided for @removeTeamTitle.
  ///
  /// In de, this message translates to:
  /// **'Team entfernen?'**
  String get removeTeamTitle;

  /// No description provided for @removeTeamBody.
  ///
  /// In de, this message translates to:
  /// **'Du entfernst „{teamName}“ nur aus deiner Liste. Das Team bleibt für den Captain und andere Mitglieder bestehen.'**
  String removeTeamBody(String teamName);

  /// No description provided for @remove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get remove;

  /// No description provided for @teamRemoved.
  ///
  /// In de, this message translates to:
  /// **'Team „{teamName}“ entfernt'**
  String teamRemoved(String teamName);

  /// No description provided for @teamRemoveError.
  ///
  /// In de, this message translates to:
  /// **'Team konnte nicht entfernt werden.'**
  String get teamRemoveError;

  /// No description provided for @ownTeams.
  ///
  /// In de, this message translates to:
  /// **'Eigene Teams'**
  String get ownTeams;

  /// No description provided for @sharedTeams.
  ///
  /// In de, this message translates to:
  /// **'Geteilte Teams'**
  String get sharedTeams;

  /// No description provided for @connectionError.
  ///
  /// In de, this message translates to:
  /// **'Verbindungsproblem'**
  String get connectionError;

  /// No description provided for @dataLoadError.
  ///
  /// In de, this message translates to:
  /// **'Daten konnten nicht geladen werden.'**
  String get dataLoadError;

  /// No description provided for @tryAgain.
  ///
  /// In de, this message translates to:
  /// **'Nochmal versuchen'**
  String get tryAgain;

  /// No description provided for @season.
  ///
  /// In de, this message translates to:
  /// **'Saison {year}'**
  String season(String year);

  /// No description provided for @gamesTitle.
  ///
  /// In de, this message translates to:
  /// **'Spiele'**
  String get gamesTitle;

  /// No description provided for @refresh.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get refresh;

  /// No description provided for @noGamesYet.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Spiele'**
  String get noGamesYet;

  /// No description provided for @noGamesSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Erstelle dein erstes Spiel in einem Team.'**
  String get noGamesSubtitle;

  /// No description provided for @home.
  ///
  /// In de, this message translates to:
  /// **'Heim'**
  String get home;

  /// No description provided for @away.
  ///
  /// In de, this message translates to:
  /// **'Auswärts'**
  String get away;

  /// No description provided for @authWelcome.
  ///
  /// In de, this message translates to:
  /// **'Willkommen'**
  String get authWelcome;

  /// No description provided for @authSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Dein Team. Deine Matches.'**
  String get authSubtitle;

  /// No description provided for @login.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get login;

  /// No description provided for @register.
  ///
  /// In de, this message translates to:
  /// **'Registrieren'**
  String get register;

  /// No description provided for @email.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get email;

  /// No description provided for @password.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen?'**
  String get forgotPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In de, this message translates to:
  /// **'Passwort bestätigen'**
  String get confirmPassword;

  /// No description provided for @passwordHint.
  ///
  /// In de, this message translates to:
  /// **'Mind. 8 Zeichen mit mind. 1 Zahl'**
  String get passwordHint;

  /// No description provided for @passwordMinLength.
  ///
  /// In de, this message translates to:
  /// **'Mindestens 8 Zeichen'**
  String get passwordMinLength;

  /// No description provided for @passwordNeedsNumber.
  ///
  /// In de, this message translates to:
  /// **'Mind. 1 Zahl erforderlich'**
  String get passwordNeedsNumber;

  /// No description provided for @invalidEmail.
  ///
  /// In de, this message translates to:
  /// **'Bitte eine gültige E-Mail eingeben.'**
  String get invalidEmail;

  /// No description provided for @enterPassword.
  ///
  /// In de, this message translates to:
  /// **'Bitte Passwort eingeben.'**
  String get enterPassword;

  /// No description provided for @passwordsMismatch.
  ///
  /// In de, this message translates to:
  /// **'Passwörter stimmen nicht überein.'**
  String get passwordsMismatch;

  /// No description provided for @loginFailed.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung fehlgeschlagen. Bitte versuche es erneut.'**
  String get loginFailed;

  /// No description provided for @registerFailed.
  ///
  /// In de, this message translates to:
  /// **'Registrierung fehlgeschlagen. Bitte versuche es erneut.'**
  String get registerFailed;

  /// No description provided for @invalidCredentials.
  ///
  /// In de, this message translates to:
  /// **'E-Mail oder Passwort ungültig.'**
  String get invalidCredentials;

  /// No description provided for @emailNotConfirmed.
  ///
  /// In de, this message translates to:
  /// **'E-Mail noch nicht bestätigt. Bitte prüfe dein Postfach.'**
  String get emailNotConfirmed;

  /// No description provided for @emailAlreadyRegistered.
  ///
  /// In de, this message translates to:
  /// **'Diese E-Mail ist bereits registriert. Bitte melde dich an.'**
  String get emailAlreadyRegistered;

  /// No description provided for @rateLimited.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Versuche. Bitte warte kurz.'**
  String get rateLimited;

  /// No description provided for @errorPrefix.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {message}'**
  String errorPrefix(String message);

  /// No description provided for @verificationPendingTitle.
  ///
  /// In de, this message translates to:
  /// **'E-Mail prüfen'**
  String get verificationPendingTitle;

  /// No description provided for @verificationPendingBody.
  ///
  /// In de, this message translates to:
  /// **'Wenn ein Konto mit dieser E-Mail existiert, haben wir dir eine Bestätigungs-E-Mail geschickt. Bitte prüfe Posteingang und Spam.'**
  String get verificationPendingBody;

  /// No description provided for @resendConfirmationEmail.
  ///
  /// In de, this message translates to:
  /// **'Bestätigungs-Mail erneut senden'**
  String get resendConfirmationEmail;

  /// No description provided for @resendEmailSuccess.
  ///
  /// In de, this message translates to:
  /// **'E-Mail wurde gesendet (sofern möglich).'**
  String get resendEmailSuccess;

  /// No description provided for @resendEmailRateLimit.
  ///
  /// In de, this message translates to:
  /// **'Bitte warte ein paar Minuten und versuche es erneut.'**
  String get resendEmailRateLimit;

  /// No description provided for @alreadyHaveAccountLogin.
  ///
  /// In de, this message translates to:
  /// **'Du hast bereits ein Konto? Anmelden'**
  String get alreadyHaveAccountLogin;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @matchDetails.
  ///
  /// In de, this message translates to:
  /// **'Spieldetails'**
  String get matchDetails;

  /// No description provided for @opponent.
  ///
  /// In de, this message translates to:
  /// **'Gegner *'**
  String get opponent;

  /// No description provided for @opponentHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. TC Zürich'**
  String get opponentHint;

  /// No description provided for @pleaseComplete.
  ///
  /// In de, this message translates to:
  /// **'Bitte ausfüllen'**
  String get pleaseComplete;

  /// No description provided for @dateAndTime.
  ///
  /// In de, this message translates to:
  /// **'Datum & Zeit'**
  String get dateAndTime;

  /// No description provided for @chooseDate.
  ///
  /// In de, this message translates to:
  /// **'Datum wählen'**
  String get chooseDate;

  /// No description provided for @chooseTime.
  ///
  /// In de, this message translates to:
  /// **'Uhrzeit wählen'**
  String get chooseTime;

  /// No description provided for @homeGame.
  ///
  /// In de, this message translates to:
  /// **'Heimspiel'**
  String get homeGame;

  /// No description provided for @awayGame.
  ///
  /// In de, this message translates to:
  /// **'Auswärtsspiel'**
  String get awayGame;

  /// No description provided for @details.
  ///
  /// In de, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @location.
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get location;

  /// No description provided for @locationHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Tennisclub Bern, Platz 3'**
  String get locationHint;

  /// No description provided for @noteOptional.
  ///
  /// In de, this message translates to:
  /// **'Notiz (optional)'**
  String get noteOptional;

  /// No description provided for @noteHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Treffpunkt 09:30'**
  String get noteHint;

  /// No description provided for @chooseDateAndTime.
  ///
  /// In de, this message translates to:
  /// **'Bitte Datum und Uhrzeit wählen'**
  String get chooseDateAndTime;

  /// No description provided for @editMatch.
  ///
  /// In de, this message translates to:
  /// **'Spiel bearbeiten'**
  String get editMatch;

  /// No description provided for @addMatch.
  ///
  /// In de, this message translates to:
  /// **'Spiel hinzufügen'**
  String get addMatch;

  /// No description provided for @saveChanges.
  ///
  /// In de, this message translates to:
  /// **'Änderungen speichern'**
  String get saveChanges;

  /// No description provided for @createMatch.
  ///
  /// In de, this message translates to:
  /// **'Spiel erstellen'**
  String get createMatch;

  /// No description provided for @matchUpdated.
  ///
  /// In de, this message translates to:
  /// **'Spiel aktualisiert'**
  String get matchUpdated;

  /// No description provided for @matchCreated.
  ///
  /// In de, this message translates to:
  /// **'Spiel erstellt'**
  String get matchCreated;

  /// No description provided for @matchCreateError.
  ///
  /// In de, this message translates to:
  /// **'Spiel konnte nicht erstellt werden. Bitte versuche es erneut.'**
  String get matchCreateError;

  /// No description provided for @lineupPublished.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung veröffentlicht'**
  String get lineupPublished;

  /// No description provided for @replacementPromoted.
  ///
  /// In de, this message translates to:
  /// **'Ersatz nachgerückt'**
  String get replacementPromoted;

  /// No description provided for @noReserveAvailable.
  ///
  /// In de, this message translates to:
  /// **'Kein Ersatz verfügbar'**
  String get noReserveAvailable;

  /// No description provided for @accountSectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto'**
  String get accountSectionTitle;

  /// No description provided for @deleteAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In de, this message translates to:
  /// **'Dein Konto und alle damit verbundenen Daten werden unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.'**
  String get deleteAccountBody;

  /// No description provided for @typeToConfirm.
  ///
  /// In de, this message translates to:
  /// **'Tippe „{confirmWord}“ zur Bestätigung'**
  String typeToConfirm(String confirmWord);

  /// No description provided for @confirmWordDelete.
  ///
  /// In de, this message translates to:
  /// **'LÖSCHEN'**
  String get confirmWordDelete;

  /// No description provided for @deleting.
  ///
  /// In de, this message translates to:
  /// **'Wird gelöscht…'**
  String get deleting;

  /// No description provided for @accountDeleted.
  ///
  /// In de, this message translates to:
  /// **'Konto gelöscht'**
  String get accountDeleted;

  /// No description provided for @accountDeleteError.
  ///
  /// In de, this message translates to:
  /// **'Konto konnte nicht gelöscht werden. Bitte versuche es erneut.'**
  String get accountDeleteError;

  /// No description provided for @teamDetailTabOverview.
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get teamDetailTabOverview;

  /// No description provided for @teamDetailTabTeam.
  ///
  /// In de, this message translates to:
  /// **'Team'**
  String get teamDetailTabTeam;

  /// No description provided for @teamDetailTabMatches.
  ///
  /// In de, this message translates to:
  /// **'Spiele'**
  String get teamDetailTabMatches;

  /// No description provided for @teamInfoBadge.
  ///
  /// In de, this message translates to:
  /// **'Team Info'**
  String get teamInfoBadge;

  /// No description provided for @teamInfoTeam.
  ///
  /// In de, this message translates to:
  /// **'Team'**
  String get teamInfoTeam;

  /// No description provided for @teamInfoClub.
  ///
  /// In de, this message translates to:
  /// **'Club'**
  String get teamInfoClub;

  /// No description provided for @teamInfoLeague.
  ///
  /// In de, this message translates to:
  /// **'Liga'**
  String get teamInfoLeague;

  /// No description provided for @teamInfoSeason.
  ///
  /// In de, this message translates to:
  /// **'Saison'**
  String get teamInfoSeason;

  /// No description provided for @teamInfoCaptain.
  ///
  /// In de, this message translates to:
  /// **'Kapitän'**
  String get teamInfoCaptain;

  /// No description provided for @nextMatch.
  ///
  /// In de, this message translates to:
  /// **'Nächstes Spiel'**
  String get nextMatch;

  /// No description provided for @playersLabel.
  ///
  /// In de, this message translates to:
  /// **'Spieler'**
  String get playersLabel;

  /// No description provided for @connectedLabel.
  ///
  /// In de, this message translates to:
  /// **'Verbunden'**
  String get connectedLabel;

  /// No description provided for @captainPlaysTitle.
  ///
  /// In de, this message translates to:
  /// **'Ich spiele selbst'**
  String get captainPlaysTitle;

  /// No description provided for @captainPlaysSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Aktiviere dies, wenn du als Captain auch spielst und in der Aufstellung erscheinen möchtest.'**
  String get captainPlaysSubtitle;

  /// No description provided for @inviteLinkTitle.
  ///
  /// In de, this message translates to:
  /// **'Einladungslink'**
  String get inviteLinkTitle;

  /// No description provided for @inviteLinkDescription.
  ///
  /// In de, this message translates to:
  /// **'Teile den Einladungslink, damit sich Spieler dem Team anschliessen können.'**
  String get inviteLinkDescription;

  /// No description provided for @shareLink.
  ///
  /// In de, this message translates to:
  /// **'Link teilen'**
  String get shareLink;

  /// No description provided for @inviteLinkCreated.
  ///
  /// In de, this message translates to:
  /// **'Einladungslink erstellt'**
  String get inviteLinkCreated;

  /// No description provided for @inviteLinkError.
  ///
  /// In de, this message translates to:
  /// **'Einladungslink konnte nicht erstellt werden.'**
  String get inviteLinkError;

  /// No description provided for @shareInviteTooltip.
  ///
  /// In de, this message translates to:
  /// **'Einladungslink teilen'**
  String get shareInviteTooltip;

  /// No description provided for @shareSubject.
  ///
  /// In de, this message translates to:
  /// **'Lineup Team-Einladung'**
  String get shareSubject;

  /// No description provided for @teamSectionCount.
  ///
  /// In de, this message translates to:
  /// **'Team ({count})'**
  String teamSectionCount(String count);

  /// No description provided for @connectedPlayersTitle.
  ///
  /// In de, this message translates to:
  /// **'Verbundene Spieler ({count})'**
  String connectedPlayersTitle(String count);

  /// No description provided for @addPlayer.
  ///
  /// In de, this message translates to:
  /// **'Spieler hinzufügen'**
  String get addPlayer;

  /// No description provided for @firstName.
  ///
  /// In de, this message translates to:
  /// **'Vorname *'**
  String get firstName;

  /// No description provided for @firstNameHint.
  ///
  /// In de, this message translates to:
  /// **'Max'**
  String get firstNameHint;

  /// No description provided for @lastName.
  ///
  /// In de, this message translates to:
  /// **'Nachname *'**
  String get lastName;

  /// No description provided for @lastNameHint.
  ///
  /// In de, this message translates to:
  /// **'Muster'**
  String get lastNameHint;

  /// No description provided for @enterFirstAndLastName.
  ///
  /// In de, this message translates to:
  /// **'Bitte Vor- und Nachname eingeben.'**
  String get enterFirstAndLastName;

  /// No description provided for @selectRanking.
  ///
  /// In de, this message translates to:
  /// **'Bitte ein Ranking auswählen.'**
  String get selectRanking;

  /// No description provided for @genericError.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen. Bitte versuche es erneut.'**
  String get genericError;

  /// No description provided for @addButton.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get addButton;

  /// No description provided for @whatsYourName.
  ///
  /// In de, this message translates to:
  /// **'Wie heisst du?'**
  String get whatsYourName;

  /// No description provided for @nicknamePrompt.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib deinen Namen ein, damit dein Team dich erkennt.'**
  String get nicknamePrompt;

  /// No description provided for @yourTeamName.
  ///
  /// In de, this message translates to:
  /// **'Dein Name im Team'**
  String get yourTeamName;

  /// No description provided for @nicknameHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Max, Sandro, Martin W.'**
  String get nicknameHint;

  /// No description provided for @minTwoChars.
  ///
  /// In de, this message translates to:
  /// **'Mindestens 2 Zeichen'**
  String get minTwoChars;

  /// No description provided for @nicknameSaveError.
  ///
  /// In de, this message translates to:
  /// **'Spieler konnte nicht hinzugefügt werden.'**
  String get nicknameSaveError;

  /// No description provided for @nameSaved.
  ///
  /// In de, this message translates to:
  /// **'Name gespeichert'**
  String get nameSaved;

  /// No description provided for @changeName.
  ///
  /// In de, this message translates to:
  /// **'Name ändern'**
  String get changeName;

  /// No description provided for @nameUpdated.
  ///
  /// In de, this message translates to:
  /// **'Name aktualisiert'**
  String get nameUpdated;

  /// No description provided for @nameSaveError.
  ///
  /// In de, this message translates to:
  /// **'Name konnte nicht gespeichert werden.'**
  String get nameSaveError;

  /// No description provided for @changeSaveError.
  ///
  /// In de, this message translates to:
  /// **'Änderung konnte nicht gespeichert werden.'**
  String get changeSaveError;

  /// No description provided for @noPlayersYet.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Spieler'**
  String get noPlayersYet;

  /// No description provided for @noPlayersEmptyBody.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Spieler vorhanden.\nFüge Spieler mit Name und Ranking hinzu.'**
  String get noPlayersEmptyBody;

  /// No description provided for @shareInviteSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Teile den Einladungslink, damit sich Spieler zuordnen können.'**
  String get shareInviteSubtitle;

  /// No description provided for @noMatchesTeamSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Erstelle ein Spiel, damit dein Team reagieren kann.'**
  String get noMatchesTeamSubtitle;

  /// No description provided for @chipOpen.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get chipOpen;

  /// No description provided for @chipAssigned.
  ///
  /// In de, this message translates to:
  /// **'Zugeordnet'**
  String get chipAssigned;

  /// No description provided for @chipYou.
  ///
  /// In de, this message translates to:
  /// **'Du'**
  String get chipYou;

  /// No description provided for @chipConnected.
  ///
  /// In de, this message translates to:
  /// **'Verbunden'**
  String get chipConnected;

  /// No description provided for @chipCaptain.
  ///
  /// In de, this message translates to:
  /// **'Captain'**
  String get chipCaptain;

  /// No description provided for @chipCaptainPlaying.
  ///
  /// In de, this message translates to:
  /// **'Captain (spielend)'**
  String get chipCaptainPlaying;

  /// No description provided for @chipPlayer.
  ///
  /// In de, this message translates to:
  /// **'Spieler'**
  String get chipPlayer;

  /// No description provided for @changeAvatarTooltip.
  ///
  /// In de, this message translates to:
  /// **'Profilbild ändern'**
  String get changeAvatarTooltip;

  /// No description provided for @claimSlotTooltip.
  ///
  /// In de, this message translates to:
  /// **'Spieler-Slot zuordnen'**
  String get claimSlotTooltip;

  /// No description provided for @changeNameTooltip.
  ///
  /// In de, this message translates to:
  /// **'Name ändern'**
  String get changeNameTooltip;

  /// No description provided for @actionError.
  ///
  /// In de, this message translates to:
  /// **'Aktion konnte nicht ausgeführt werden.'**
  String get actionError;

  /// No description provided for @avatarUpdated.
  ///
  /// In de, this message translates to:
  /// **'Profilbild aktualisiert'**
  String get avatarUpdated;

  /// No description provided for @avatarUploadError.
  ///
  /// In de, this message translates to:
  /// **'Bild konnte nicht hochgeladen werden.'**
  String get avatarUploadError;

  /// No description provided for @storageSetupRequired.
  ///
  /// In de, this message translates to:
  /// **'Storage Setup erforderlich'**
  String get storageSetupRequired;

  /// No description provided for @storageSetupBody.
  ///
  /// In de, this message translates to:
  /// **'Der Storage-Bucket „profile-photos“ wurde noch nicht angelegt.\nBitte folge diesen Schritten:'**
  String get storageSetupBody;

  /// No description provided for @storageStep1.
  ///
  /// In de, this message translates to:
  /// **'Supabase Dashboard → Storage → „New bucket“'**
  String get storageStep1;

  /// No description provided for @storageStep2.
  ///
  /// In de, this message translates to:
  /// **'Name exakt: profile-photos'**
  String get storageStep2;

  /// No description provided for @storageStep3.
  ///
  /// In de, this message translates to:
  /// **'Public: OFF (private)'**
  String get storageStep3;

  /// No description provided for @storageStep4.
  ///
  /// In de, this message translates to:
  /// **'SQL Editor → untenstehende Policies ausführen'**
  String get storageStep4;

  /// No description provided for @sqlCopied.
  ///
  /// In de, this message translates to:
  /// **'SQL in Zwischenablage kopiert'**
  String get sqlCopied;

  /// No description provided for @copySql.
  ///
  /// In de, this message translates to:
  /// **'SQL kopieren'**
  String get copySql;

  /// No description provided for @closeButton.
  ///
  /// In de, this message translates to:
  /// **'Schliessen'**
  String get closeButton;

  /// No description provided for @notificationsTooltip.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen'**
  String get notificationsTooltip;

  /// No description provided for @removePlayer.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get removePlayer;

  /// No description provided for @matchTabOverview.
  ///
  /// In de, this message translates to:
  /// **'Übersicht'**
  String get matchTabOverview;

  /// No description provided for @matchTabLineup.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung'**
  String get matchTabLineup;

  /// No description provided for @matchTabMore.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get matchTabMore;

  /// No description provided for @editLabel.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get editLabel;

  /// No description provided for @matchConfirmedProgress.
  ///
  /// In de, this message translates to:
  /// **'{yes} von {total} zugesagt'**
  String matchConfirmedProgress(String yes, String total);

  /// No description provided for @myAvailability.
  ///
  /// In de, this message translates to:
  /// **'Meine Verfügbarkeit'**
  String get myAvailability;

  /// No description provided for @availYes.
  ///
  /// In de, this message translates to:
  /// **'Zugesagt'**
  String get availYes;

  /// No description provided for @availNo.
  ///
  /// In de, this message translates to:
  /// **'Abgesagt'**
  String get availNo;

  /// No description provided for @availMaybe.
  ///
  /// In de, this message translates to:
  /// **'Unsicher'**
  String get availMaybe;

  /// No description provided for @availNoResponse.
  ///
  /// In de, this message translates to:
  /// **'Keine Antwort'**
  String get availNoResponse;

  /// No description provided for @availabilitiesTitle.
  ///
  /// In de, this message translates to:
  /// **'Verfügbarkeiten'**
  String get availabilitiesTitle;

  /// No description provided for @respondedProgress.
  ///
  /// In de, this message translates to:
  /// **'{responded} von {total} haben geantwortet'**
  String respondedProgress(String responded, String total);

  /// No description provided for @playerAvailabilities.
  ///
  /// In de, this message translates to:
  /// **'Verfügbarkeiten der Spieler'**
  String get playerAvailabilities;

  /// No description provided for @subRequestSection.
  ///
  /// In de, this message translates to:
  /// **'Ersatz'**
  String get subRequestSection;

  /// No description provided for @noSubRequests.
  ///
  /// In de, this message translates to:
  /// **'Keine Ersatzanfragen vorhanden. Bei Absagen kannst du hier Ersatz anfragen.'**
  String get noSubRequests;

  /// No description provided for @generateLineupTitle.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung generieren'**
  String get generateLineupTitle;

  /// No description provided for @generateButton.
  ///
  /// In de, this message translates to:
  /// **'Generieren'**
  String get generateButton;

  /// No description provided for @lineupGenerateDescription.
  ///
  /// In de, this message translates to:
  /// **'Die Aufstellung wird anhand des Rankings und der Verfügbarkeiten erstellt.\nDu kannst danach manuell tauschen.\n\nEine bestehende Aufstellung wird überschrieben.'**
  String get lineupGenerateDescription;

  /// No description provided for @starterLabel.
  ///
  /// In de, this message translates to:
  /// **'Starter'**
  String get starterLabel;

  /// No description provided for @reserveLabel.
  ///
  /// In de, this message translates to:
  /// **'Ersatz'**
  String get reserveLabel;

  /// No description provided for @includeMaybeTitle.
  ///
  /// In de, this message translates to:
  /// **'Unsichere berücksichtigen'**
  String get includeMaybeTitle;

  /// No description provided for @includeMaybeSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Spieler mit „Unsicher“ werden ergänzend aufgestellt.'**
  String get includeMaybeSubtitle;

  /// No description provided for @lineupCreatedToast.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung erstellt: {starters} Starter, {reserves} Ersatz'**
  String lineupCreatedToast(String starters, String reserves);

  /// No description provided for @lineupTitle.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung'**
  String get lineupTitle;

  /// No description provided for @lineupStatusDraft.
  ///
  /// In de, this message translates to:
  /// **'Entwurf'**
  String get lineupStatusDraft;

  /// No description provided for @lineupStatusPublished.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlicht'**
  String get lineupStatusPublished;

  /// No description provided for @allSlotsOccupied.
  ///
  /// In de, this message translates to:
  /// **'Alle Plätze besetzt'**
  String get allSlotsOccupied;

  /// No description provided for @slotsFreeSingle.
  ///
  /// In de, this message translates to:
  /// **'1 Platz frei'**
  String get slotsFreeSingle;

  /// No description provided for @slotsFree.
  ///
  /// In de, this message translates to:
  /// **'{count} Plätze frei'**
  String slotsFree(String count);

  /// No description provided for @regenerateButton.
  ///
  /// In de, this message translates to:
  /// **'Neu generieren'**
  String get regenerateButton;

  /// No description provided for @noLineupYet.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Aufstellung vorhanden.'**
  String get noLineupYet;

  /// No description provided for @noLineupYetAdmin.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Aufstellung vorhanden.\nTippe auf „Generieren“, um eine zu erstellen.'**
  String get noLineupYetAdmin;

  /// No description provided for @captainCreatingLineup.
  ///
  /// In de, this message translates to:
  /// **'Captain erstellt gerade die Aufstellung …'**
  String get captainCreatingLineup;

  /// No description provided for @subChainActive.
  ///
  /// In de, this message translates to:
  /// **'Ersatzkette aktiv: Bei Absage rückt der nächste Ersatz automatisch nach.'**
  String get subChainActive;

  /// No description provided for @starterCountHeader.
  ///
  /// In de, this message translates to:
  /// **'Starter ({count})'**
  String starterCountHeader(String count);

  /// No description provided for @reserveCountHeader.
  ///
  /// In de, this message translates to:
  /// **'Ersatz ({count})'**
  String reserveCountHeader(String count);

  /// No description provided for @sendLineupToTeam.
  ///
  /// In de, this message translates to:
  /// **'Info an Team senden'**
  String get sendLineupToTeam;

  /// No description provided for @lineupPublishedBanner.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung veröffentlicht. Absagen lösen automatisches Nachrücken aus.'**
  String get lineupPublishedBanner;

  /// No description provided for @youStarter.
  ///
  /// In de, this message translates to:
  /// **'Du · Starter'**
  String get youStarter;

  /// No description provided for @youReserve.
  ///
  /// In de, this message translates to:
  /// **'Du · Ersatz'**
  String get youReserve;

  /// No description provided for @publishLineupTitle.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung veröffentlichen?'**
  String get publishLineupTitle;

  /// No description provided for @publishSendButton.
  ///
  /// In de, this message translates to:
  /// **'Senden'**
  String get publishSendButton;

  /// No description provided for @publishLineupBody.
  ///
  /// In de, this message translates to:
  /// **'Alle Team-Mitglieder werden über die Aufstellung informiert (In-App + Push).'**
  String get publishLineupBody;

  /// No description provided for @publishLineupConfirm.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du die Aufstellung jetzt senden?'**
  String get publishLineupConfirm;

  /// No description provided for @lineupPublishedToast.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung veröffentlicht – {recipients} Benachrichtigungen gesendet'**
  String lineupPublishedToast(String recipients);

  /// No description provided for @violationSingle.
  ///
  /// In de, this message translates to:
  /// **'⚠️ 1 Regelverstoss erkannt'**
  String get violationSingle;

  /// No description provided for @violationMultiple.
  ///
  /// In de, this message translates to:
  /// **'⚠️ {count} Regelverstösse erkannt'**
  String violationMultiple(String count);

  /// No description provided for @violationMore.
  ///
  /// In de, this message translates to:
  /// **'… und {count} weitere'**
  String violationMore(String count);

  /// No description provided for @publishAnyway.
  ///
  /// In de, this message translates to:
  /// **'Veröffentlichung trotzdem möglich.'**
  String get publishAnyway;

  /// No description provided for @lineupPublishedNoReorder.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung ist veröffentlicht – Reihenfolge kann nicht mehr geändert werden.'**
  String get lineupPublishedNoReorder;

  /// No description provided for @lineupBeingGenerated.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung wird generiert …'**
  String get lineupBeingGenerated;

  /// No description provided for @lineupBeingPublished.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung wird veröffentlicht …'**
  String get lineupBeingPublished;

  /// No description provided for @reorderNotPossible.
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge ändern ist momentan nicht möglich.'**
  String get reorderNotPossible;

  /// No description provided for @deleteMatchTitle.
  ///
  /// In de, this message translates to:
  /// **'Spiel löschen?'**
  String get deleteMatchTitle;

  /// No description provided for @deleteMatchBody.
  ///
  /// In de, this message translates to:
  /// **'Möchtest du das Spiel gegen „{opponent}“ wirklich löschen?\n\nAlle Verfügbarkeiten und Aufstellungen gehen verloren.'**
  String deleteMatchBody(String opponent);

  /// No description provided for @matchDeleted.
  ///
  /// In de, this message translates to:
  /// **'Spiel gelöscht'**
  String get matchDeleted;

  /// No description provided for @subRequestSentToast.
  ///
  /// In de, this message translates to:
  /// **'Ersatzanfrage an {name} gesendet'**
  String subRequestSentToast(String name);

  /// No description provided for @noSubAvailable.
  ///
  /// In de, this message translates to:
  /// **'Kein verfügbarer Ersatzspieler gefunden.'**
  String get noSubAvailable;

  /// No description provided for @subRequestAcceptedToast.
  ///
  /// In de, this message translates to:
  /// **'Ersatzanfrage angenommen'**
  String get subRequestAcceptedToast;

  /// No description provided for @subRequestDeclinedToast.
  ///
  /// In de, this message translates to:
  /// **'Ersatzanfrage abgelehnt'**
  String get subRequestDeclinedToast;

  /// No description provided for @somethingWentWrong.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen.'**
  String get somethingWentWrong;

  /// No description provided for @subRequestsTitle.
  ///
  /// In de, this message translates to:
  /// **'Ersatzanfragen'**
  String get subRequestsTitle;

  /// No description provided for @pendingCountChip.
  ///
  /// In de, this message translates to:
  /// **'{count} ausstehend'**
  String pendingCountChip(String count);

  /// No description provided for @pendingRequestsLabel.
  ///
  /// In de, this message translates to:
  /// **'Ausstehende Anfragen'**
  String get pendingRequestsLabel;

  /// No description provided for @youWereAsked.
  ///
  /// In de, this message translates to:
  /// **'Du wurdest angefragt:'**
  String get youWereAsked;

  /// No description provided for @subForPlayer.
  ///
  /// In de, this message translates to:
  /// **'Ersatz für {name}'**
  String subForPlayer(String name);

  /// No description provided for @canYouStepIn.
  ///
  /// In de, this message translates to:
  /// **'Kannst du einspringen?'**
  String get canYouStepIn;

  /// No description provided for @timeExpired.
  ///
  /// In de, this message translates to:
  /// **'Zeit abgelaufen'**
  String get timeExpired;

  /// No description provided for @acceptTooltip.
  ///
  /// In de, this message translates to:
  /// **'Annehmen'**
  String get acceptTooltip;

  /// No description provided for @declineTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get declineTooltip;

  /// No description provided for @requestHistory.
  ///
  /// In de, this message translates to:
  /// **'Anfragen-Verlauf:'**
  String get requestHistory;

  /// No description provided for @subForPlayerHistory.
  ///
  /// In de, this message translates to:
  /// **'{subName} für {originalName}'**
  String subForPlayerHistory(String subName, String originalName);

  /// No description provided for @chipWaiting.
  ///
  /// In de, this message translates to:
  /// **'Wartet auf Antwort'**
  String get chipWaiting;

  /// No description provided for @chipAccepted.
  ///
  /// In de, this message translates to:
  /// **'Angenommen'**
  String get chipAccepted;

  /// No description provided for @chipDeclined.
  ///
  /// In de, this message translates to:
  /// **'Abgelehnt'**
  String get chipDeclined;

  /// No description provided for @subButton.
  ///
  /// In de, this message translates to:
  /// **'Ersatz'**
  String get subButton;

  /// No description provided for @sectionRides.
  ///
  /// In de, this message translates to:
  /// **'Fahrten'**
  String get sectionRides;

  /// No description provided for @carpoolsTitle.
  ///
  /// In de, this message translates to:
  /// **'Fahrgemeinschaften'**
  String get carpoolsTitle;

  /// No description provided for @iDriveButton.
  ///
  /// In de, this message translates to:
  /// **'Ich fahre'**
  String get iDriveButton;

  /// No description provided for @noCarpoolsYet.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fahrgemeinschaften vorhanden.'**
  String get noCarpoolsYet;

  /// No description provided for @noCarpoolsHint.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fahrgemeinschaften. Biete eine Mitfahrgelegenheit an.'**
  String get noCarpoolsHint;

  /// No description provided for @youSuffix.
  ///
  /// In de, this message translates to:
  /// **'(du)'**
  String get youSuffix;

  /// No description provided for @carpoolFull.
  ///
  /// In de, this message translates to:
  /// **'Voll'**
  String get carpoolFull;

  /// No description provided for @joinRideButton.
  ///
  /// In de, this message translates to:
  /// **'Mitfahren'**
  String get joinRideButton;

  /// No description provided for @leaveRideButton.
  ///
  /// In de, this message translates to:
  /// **'Aussteigen'**
  String get leaveRideButton;

  /// No description provided for @joinedRideToast.
  ///
  /// In de, this message translates to:
  /// **'Du fährst mit'**
  String get joinedRideToast;

  /// No description provided for @joinRideError.
  ///
  /// In de, this message translates to:
  /// **'Mitfahren konnte nicht gespeichert werden.'**
  String get joinRideError;

  /// No description provided for @leftRideToast.
  ///
  /// In de, this message translates to:
  /// **'Ausgestiegen'**
  String get leftRideToast;

  /// No description provided for @leaveRideError.
  ///
  /// In de, this message translates to:
  /// **'Aussteigen konnte nicht gespeichert werden.'**
  String get leaveRideError;

  /// No description provided for @deleteCarpoolTitle.
  ///
  /// In de, this message translates to:
  /// **'Fahrgemeinschaft löschen?'**
  String get deleteCarpoolTitle;

  /// No description provided for @deleteCarpoolBody.
  ///
  /// In de, this message translates to:
  /// **'Alle Mitfahrer werden entfernt.'**
  String get deleteCarpoolBody;

  /// No description provided for @editCarpoolTitle.
  ///
  /// In de, this message translates to:
  /// **'Fahrgemeinschaft bearbeiten'**
  String get editCarpoolTitle;

  /// No description provided for @seatsQuestion.
  ///
  /// In de, this message translates to:
  /// **'Wie viele Plätze bietest du an?'**
  String get seatsQuestion;

  /// No description provided for @departureLocationLabel.
  ///
  /// In de, this message translates to:
  /// **'Abfahrtsort'**
  String get departureLocationLabel;

  /// No description provided for @departureLocationHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Bahnhof Bern'**
  String get departureLocationHint;

  /// No description provided for @departureTimeWithValue.
  ///
  /// In de, this message translates to:
  /// **'Abfahrt: {time}'**
  String departureTimeWithValue(String time);

  /// No description provided for @departureTimeOptional.
  ///
  /// In de, this message translates to:
  /// **'Abfahrtszeit (optional)'**
  String get departureTimeOptional;

  /// No description provided for @changeTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get changeTooltip;

  /// No description provided for @setTooltip.
  ///
  /// In de, this message translates to:
  /// **'Setzen'**
  String get setTooltip;

  /// No description provided for @removeTooltipLabel.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get removeTooltipLabel;

  /// No description provided for @carpoolNoteHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Treffpunkt Parkplatz'**
  String get carpoolNoteHint;

  /// No description provided for @carpoolSavedToast.
  ///
  /// In de, this message translates to:
  /// **'Fahrgemeinschaft gespeichert'**
  String get carpoolSavedToast;

  /// No description provided for @carpoolCreatedReloadToast.
  ///
  /// In de, this message translates to:
  /// **'Fahrgemeinschaft erstellt. Bitte lade die Seite neu.'**
  String get carpoolCreatedReloadToast;

  /// No description provided for @departAtFormat.
  ///
  /// In de, this message translates to:
  /// **'{date} um {time}'**
  String departAtFormat(String date, String time);

  /// No description provided for @sectionDinner.
  ///
  /// In de, this message translates to:
  /// **'Essen'**
  String get sectionDinner;

  /// No description provided for @answeredOfTotal.
  ///
  /// In de, this message translates to:
  /// **'{answered} von {total}'**
  String answeredOfTotal(String answered, String total);

  /// No description provided for @yourRsvp.
  ///
  /// In de, this message translates to:
  /// **'Deine Zusage'**
  String get yourRsvp;

  /// No description provided for @dinnerYes.
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get dinnerYes;

  /// No description provided for @dinnerNo.
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get dinnerNo;

  /// No description provided for @dinnerMaybe.
  ///
  /// In de, this message translates to:
  /// **'Unsicher'**
  String get dinnerMaybe;

  /// No description provided for @dinnerNoteHint.
  ///
  /// In de, this message translates to:
  /// **'Notiz (z.B. „komme später“)'**
  String get dinnerNoteHint;

  /// No description provided for @dinnerSaveError.
  ///
  /// In de, this message translates to:
  /// **'Speichern nicht möglich. Bitte versuche es erneut.'**
  String get dinnerSaveError;

  /// No description provided for @participantsTitle.
  ///
  /// In de, this message translates to:
  /// **'Teilnehmer'**
  String get participantsTitle;

  /// No description provided for @sectionExpenses.
  ///
  /// In de, this message translates to:
  /// **'Spesen'**
  String get sectionExpenses;

  /// No description provided for @expenseTotal.
  ///
  /// In de, this message translates to:
  /// **'Total'**
  String get expenseTotal;

  /// No description provided for @perPersonLabel.
  ///
  /// In de, this message translates to:
  /// **'Pro Kopf ({count} Pers.)'**
  String perPersonLabel(String count);

  /// No description provided for @paidLabel.
  ///
  /// In de, this message translates to:
  /// **'Bezahlt'**
  String get paidLabel;

  /// No description provided for @firstConfirmDinner.
  ///
  /// In de, this message translates to:
  /// **'Zuerst unter „Essen“ zusagen, bevor Spesen erfasst werden können.'**
  String get firstConfirmDinner;

  /// No description provided for @addExpenseButton.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe hinzufügen'**
  String get addExpenseButton;

  /// No description provided for @noExpensesYet.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Spesen erfasst. Lege eine neue Ausgabe an.'**
  String get noExpensesYet;

  /// No description provided for @noExpensesPossible.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Spesen möglich. Zuerst unter „Essen“ zusagen.'**
  String get noExpensesPossible;

  /// No description provided for @paidByLabel.
  ///
  /// In de, this message translates to:
  /// **'Bezahlt von {name}'**
  String paidByLabel(String name);

  /// No description provided for @perPersonAmountLabel.
  ///
  /// In de, this message translates to:
  /// **'{amount}/Pers.'**
  String perPersonAmountLabel(String amount);

  /// No description provided for @paidOfShareCount.
  ///
  /// In de, this message translates to:
  /// **'{paid}/{total} bezahlt'**
  String paidOfShareCount(String paid, String total);

  /// No description provided for @sharePaid.
  ///
  /// In de, this message translates to:
  /// **'Bezahlt'**
  String get sharePaid;

  /// No description provided for @shareOpen.
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get shareOpen;

  /// No description provided for @deleteExpenseTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe löschen'**
  String get deleteExpenseTooltip;

  /// No description provided for @markedAsPaid.
  ///
  /// In de, this message translates to:
  /// **'Als bezahlt markiert'**
  String get markedAsPaid;

  /// No description provided for @markedAsOpen.
  ///
  /// In de, this message translates to:
  /// **'Als offen markiert'**
  String get markedAsOpen;

  /// No description provided for @expenseTitleField.
  ///
  /// In de, this message translates to:
  /// **'Titel *'**
  String get expenseTitleField;

  /// No description provided for @expenseTitleHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Pizza, Getränke'**
  String get expenseTitleHint;

  /// No description provided for @expenseAmountField.
  ///
  /// In de, this message translates to:
  /// **'Betrag (CHF) *'**
  String get expenseAmountField;

  /// No description provided for @expenseAmountHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. 45.50'**
  String get expenseAmountHint;

  /// No description provided for @currencyPrefix.
  ///
  /// In de, this message translates to:
  /// **'CHF '**
  String get currencyPrefix;

  /// No description provided for @expenseNoteHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Restaurant Adler'**
  String get expenseNoteHint;

  /// No description provided for @expenseDistribution.
  ///
  /// In de, this message translates to:
  /// **'Wird gleichmässig auf alle {count} Dinner-Teilnehmer (Ja) verteilt.'**
  String expenseDistribution(String count);

  /// No description provided for @enterTitleValidation.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib einen Titel ein.'**
  String get enterTitleValidation;

  /// No description provided for @enterAmountValidation.
  ///
  /// In de, this message translates to:
  /// **'Bitte gib einen gültigen Betrag ein.'**
  String get enterAmountValidation;

  /// No description provided for @expenseCreatedToast.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe „{title}“ (CHF {amount}) erstellt'**
  String expenseCreatedToast(String title, String amount);

  /// No description provided for @deleteExpenseTitle.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe löschen?'**
  String get deleteExpenseTitle;

  /// No description provided for @deleteExpenseBody.
  ///
  /// In de, this message translates to:
  /// **'„{title}“ ({amount}) und alle Anteile werden gelöscht.'**
  String deleteExpenseBody(String title, String amount);

  /// No description provided for @expenseDeletedToast.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe „{title}“ gelöscht'**
  String expenseDeletedToast(String title);

  /// No description provided for @roleCaptainSuffix.
  ///
  /// In de, this message translates to:
  /// **' (Captain)'**
  String get roleCaptainSuffix;

  /// No description provided for @unknownPlayer.
  ///
  /// In de, this message translates to:
  /// **'Unbekannt'**
  String get unknownPlayer;

  /// No description provided for @lineupReorderHint.
  ///
  /// In de, this message translates to:
  /// **'Halte ☰ und ziehe um Positionen zu tauschen'**
  String get lineupReorderHint;

  /// No description provided for @claimConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Spieler bestätigen'**
  String get claimConfirmTitle;

  /// No description provided for @claimConfirmCta.
  ///
  /// In de, this message translates to:
  /// **'Ja, das bin ich'**
  String get claimConfirmCta;

  /// No description provided for @claimConfirmBody.
  ///
  /// In de, this message translates to:
  /// **'Bist du „{label}“?'**
  String claimConfirmBody(String label);

  /// No description provided for @claimWelcomeToast.
  ///
  /// In de, this message translates to:
  /// **'Willkommen, {name}!'**
  String claimWelcomeToast(String name);

  /// No description provided for @claimWhoAreYou.
  ///
  /// In de, this message translates to:
  /// **'Wer bist du?'**
  String get claimWhoAreYou;

  /// No description provided for @commonSkip.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get commonSkip;

  /// No description provided for @claimPickName.
  ///
  /// In de, this message translates to:
  /// **'Wähle deinen Namen aus der Liste,\ndamit das Team dich zuordnen kann.'**
  String get claimPickName;

  /// No description provided for @claimSearchHint.
  ///
  /// In de, this message translates to:
  /// **'Name suchen…'**
  String get claimSearchHint;

  /// No description provided for @claimNoSlotTitle.
  ///
  /// In de, this message translates to:
  /// **'Kein freier Platz'**
  String get claimNoSlotTitle;

  /// No description provided for @claimNoSlotBody.
  ///
  /// In de, this message translates to:
  /// **'Dein Captain hat noch keine Spieler angelegt\noder alle Plätze sind bereits vergeben.'**
  String get claimNoSlotBody;

  /// No description provided for @notifLoadError.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen konnten nicht geladen werden.'**
  String get notifLoadError;

  /// No description provided for @matchLoadError.
  ///
  /// In de, this message translates to:
  /// **'Spiel konnte nicht geladen werden.'**
  String get matchLoadError;

  /// No description provided for @notifTitleWithCount.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigungen ({count})'**
  String notifTitleWithCount(String count);

  /// No description provided for @markAllRead.
  ///
  /// In de, this message translates to:
  /// **'Alle gelesen'**
  String get markAllRead;

  /// No description provided for @allReadTitle.
  ///
  /// In de, this message translates to:
  /// **'Alles gelesen'**
  String get allReadTitle;

  /// No description provided for @allReadSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Neue Benachrichtigungen erscheinen automatisch hier.'**
  String get allReadSubtitle;

  /// No description provided for @timeJustNow.
  ///
  /// In de, this message translates to:
  /// **'gerade eben'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In de, this message translates to:
  /// **'vor {minutes} Min.'**
  String timeMinutesAgo(String minutes);

  /// No description provided for @timeHoursAgo.
  ///
  /// In de, this message translates to:
  /// **'vor {hours} Std.'**
  String timeHoursAgo(String hours);

  /// No description provided for @timeDaysAgo.
  ///
  /// In de, this message translates to:
  /// **'vor {days} Tagen'**
  String timeDaysAgo(String days);

  /// No description provided for @forgotPasswordAppBar.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen'**
  String get forgotPasswordAppBar;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort zurücksetzen'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordInstructions.
  ///
  /// In de, this message translates to:
  /// **'Gib deine E-Mail-Adresse ein und wir senden dir einen Link zum Zurücksetzen.'**
  String get resetPasswordInstructions;

  /// No description provided for @emailSentTitle.
  ///
  /// In de, this message translates to:
  /// **'E-Mail gesendet!'**
  String get emailSentTitle;

  /// No description provided for @resetPasswordSentBody.
  ///
  /// In de, this message translates to:
  /// **'Prüfe dein Postfach und klicke auf den Link, um ein neues Passwort zu setzen.'**
  String get resetPasswordSentBody;

  /// No description provided for @backToSignIn.
  ///
  /// In de, this message translates to:
  /// **'Zurück zur Anmeldung'**
  String get backToSignIn;

  /// No description provided for @sendLinkButton.
  ///
  /// In de, this message translates to:
  /// **'Link senden'**
  String get sendLinkButton;

  /// No description provided for @emailSendError.
  ///
  /// In de, this message translates to:
  /// **'E-Mail konnte nicht gesendet werden.'**
  String get emailSendError;

  /// No description provided for @sportSelectionTitle.
  ///
  /// In de, this message translates to:
  /// **'Sportart wählen'**
  String get sportSelectionTitle;

  /// No description provided for @sportSelectionSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Welche Sportart spielt dein Team?'**
  String get sportSelectionSubtitle;

  /// No description provided for @eventsLoadError.
  ///
  /// In de, this message translates to:
  /// **'Events konnten nicht geladen werden.'**
  String get eventsLoadError;

  /// No description provided for @matchUnavailableDeleted.
  ///
  /// In de, this message translates to:
  /// **'Match nicht verfügbar (gelöscht oder archiviert).'**
  String get matchUnavailableDeleted;

  /// No description provided for @matchUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Match nicht verfügbar.'**
  String get matchUnavailable;

  /// No description provided for @noNewEvents.
  ///
  /// In de, this message translates to:
  /// **'Keine neuen Events'**
  String get noNewEvents;

  /// No description provided for @noNewEventsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Sobald es Neuigkeiten gibt, siehst du sie hier.'**
  String get noNewEventsSubtitle;

  /// No description provided for @teamFilterLabel.
  ///
  /// In de, this message translates to:
  /// **'Team-Filter'**
  String get teamFilterLabel;

  /// No description provided for @allTeams.
  ///
  /// In de, this message translates to:
  /// **'Alle Teams'**
  String get allTeams;

  /// No description provided for @createTeamTitle.
  ///
  /// In de, this message translates to:
  /// **'Team erstellen'**
  String get createTeamTitle;

  /// No description provided for @teamNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Club Name / Team Name *'**
  String get teamNameLabel;

  /// No description provided for @teamNameHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. TC Winterthur 1'**
  String get teamNameHint;

  /// No description provided for @leagueLabel.
  ///
  /// In de, this message translates to:
  /// **'Liga (optional)'**
  String get leagueLabel;

  /// No description provided for @leagueHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. 3. Liga Herren'**
  String get leagueHint;

  /// No description provided for @seasonYearLabel.
  ///
  /// In de, this message translates to:
  /// **'Saison Jahr'**
  String get seasonYearLabel;

  /// No description provided for @captainNameRequired.
  ///
  /// In de, this message translates to:
  /// **'Dein Name im Team *'**
  String get captainNameRequired;

  /// No description provided for @captainNamePrompt.
  ///
  /// In de, this message translates to:
  /// **'Dein Name, damit dein Team dich erkennt.'**
  String get captainNamePrompt;

  /// No description provided for @createTeamPlaysSelfSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Aktiviere dies, wenn du als Captain auch spielst.'**
  String get createTeamPlaysSelfSubtitle;

  /// No description provided for @createButton.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get createButton;

  /// No description provided for @teamCreatedToast.
  ///
  /// In de, this message translates to:
  /// **'Team erstellt'**
  String get teamCreatedToast;

  /// No description provided for @teamCreateError.
  ///
  /// In de, this message translates to:
  /// **'Team konnte nicht erstellt werden. Bitte versuche es erneut.'**
  String get teamCreateError;

  /// No description provided for @enterTeamName.
  ///
  /// In de, this message translates to:
  /// **'Bitte Team Name eingeben.'**
  String get enterTeamName;

  /// No description provided for @enterCaptainName.
  ///
  /// In de, this message translates to:
  /// **'Bitte deinen Namen eingeben (min. 2 Zeichen).'**
  String get enterCaptainName;

  /// No description provided for @invalidSeasonYear.
  ///
  /// In de, this message translates to:
  /// **'Bitte gültiges Saison-Jahr eingeben.'**
  String get invalidSeasonYear;

  /// No description provided for @selectRankingError.
  ///
  /// In de, this message translates to:
  /// **'Bitte Ranking auswählen.'**
  String get selectRankingError;

  /// No description provided for @countryLabel.
  ///
  /// In de, this message translates to:
  /// **'Land *'**
  String get countryLabel;

  /// No description provided for @rankingLabelRequired.
  ///
  /// In de, this message translates to:
  /// **'Ranking *'**
  String get rankingLabelRequired;

  /// No description provided for @rankingAvailableSection.
  ///
  /// In de, this message translates to:
  /// **'Verfügbar'**
  String get rankingAvailableSection;

  /// No description provided for @dropdownHint.
  ///
  /// In de, this message translates to:
  /// **'Bitte auswählen'**
  String get dropdownHint;

  /// No description provided for @notifTitleLineup.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung'**
  String get notifTitleLineup;

  /// No description provided for @notifTitleSubRequest.
  ///
  /// In de, this message translates to:
  /// **'Ersatzanfrage'**
  String get notifTitleSubRequest;

  /// No description provided for @notifTitlePromotion.
  ///
  /// In de, this message translates to:
  /// **'Nachrücker'**
  String get notifTitlePromotion;

  /// No description provided for @notifTitleAutoPromotion.
  ///
  /// In de, this message translates to:
  /// **'Auto-Nachrücken'**
  String get notifTitleAutoPromotion;

  /// No description provided for @notifTitleLineupGenerated.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung erstellt'**
  String get notifTitleLineupGenerated;

  /// No description provided for @notifTitleConfirmation.
  ///
  /// In de, this message translates to:
  /// **'Bestätigung'**
  String get notifTitleConfirmation;

  /// No description provided for @notifTitleWarning.
  ///
  /// In de, this message translates to:
  /// **'Achtung'**
  String get notifTitleWarning;

  /// No description provided for @notifTitlePromoted.
  ///
  /// In de, this message translates to:
  /// **'Beförderung'**
  String get notifTitlePromoted;

  /// No description provided for @notifBodyLineupOnline.
  ///
  /// In de, this message translates to:
  /// **'Die Aufstellung ist online. Schau sie dir an!'**
  String get notifBodyLineupOnline;

  /// No description provided for @notifBodySelectedAs.
  ///
  /// In de, this message translates to:
  /// **'Du wurdest als {role} (Pos. {position}) aufgestellt'**
  String notifBodySelectedAs(String role, String position);

  /// No description provided for @notifBodyReserveConfirm.
  ///
  /// In de, this message translates to:
  /// **'Du bist Ersatz {position}. Bitte bestätige.'**
  String notifBodyReserveConfirm(String position);

  /// No description provided for @notifBodyPromotedToStarter.
  ///
  /// In de, this message translates to:
  /// **'Du wurdest zum Starter (Pos. {position}) befördert 🎉'**
  String notifBodyPromotedToStarter(String position);

  /// No description provided for @notifBodyAutoPromoted.
  ///
  /// In de, this message translates to:
  /// **'Du bist als Ersatz nachgerückt und spielst nun mit 🎉'**
  String get notifBodyAutoPromoted;

  /// No description provided for @notifBodyAutoPromotionCaptain.
  ///
  /// In de, this message translates to:
  /// **'Auto-Nachrücken: {inName} ersetzt {outName}'**
  String notifBodyAutoPromotionCaptain(String inName, String outName);

  /// No description provided for @notifBodyNoReserve.
  ///
  /// In de, this message translates to:
  /// **'{absent} hat abgesagt – kein Ersatz verfügbar!'**
  String notifBodyNoReserve(String absent);

  /// No description provided for @notifBodyLineupCreated.
  ///
  /// In de, this message translates to:
  /// **'Aufstellung erstellt: {starters} Starter, {reserves} Ersatz'**
  String notifBodyLineupCreated(String starters, String reserves);

  /// No description provided for @notifBodyPlayerConfirmed.
  ///
  /// In de, this message translates to:
  /// **'Ein Spieler hat bestätigt'**
  String get notifBodyPlayerConfirmed;

  /// No description provided for @notifBodyNoReservesLeft.
  ///
  /// In de, this message translates to:
  /// **'Keine Ersatzspieler mehr verfügbar!'**
  String get notifBodyNoReservesLeft;

  /// No description provided for @notifBodyPromotedToPos.
  ///
  /// In de, this message translates to:
  /// **'Du wurdest zum Starter befördert (Pos. {position}) 🎉'**
  String notifBodyPromotedToPos(String position);

  /// No description provided for @notifBodyRosterChanged.
  ///
  /// In de, this message translates to:
  /// **'Die Aufstellung wurde geändert'**
  String get notifBodyRosterChanged;

  /// No description provided for @notifBodyNeedsResponse.
  ///
  /// In de, this message translates to:
  /// **'Bitte bestätige deine Aufstellung'**
  String get notifBodyNeedsResponse;

  /// No description provided for @eventBodyReplaced.
  ///
  /// In de, this message translates to:
  /// **'{inName} ersetzt {outName}'**
  String eventBodyReplaced(String inName, String outName);

  /// No description provided for @editExpenseTitle.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe bearbeiten'**
  String get editExpenseTitle;

  /// No description provided for @expenseUpdatedToast.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe „{title}“ aktualisiert'**
  String expenseUpdatedToast(String title);

  /// No description provided for @editExpenseTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe bearbeiten'**
  String get editExpenseTooltip;

  /// No description provided for @deleteAllNotifications.
  ///
  /// In de, this message translates to:
  /// **'Alle löschen'**
  String get deleteAllNotifications;

  /// No description provided for @deleteNotificationConfirm.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigung löschen?'**
  String get deleteNotificationConfirm;

  /// No description provided for @deleteAllNotificationsConfirm.
  ///
  /// In de, this message translates to:
  /// **'Alle Benachrichtigungen löschen?'**
  String get deleteAllNotificationsConfirm;

  /// No description provided for @deleteAllNotificationsBody.
  ///
  /// In de, this message translates to:
  /// **'Alle Benachrichtigungen werden unwiderruflich gelöscht.'**
  String get deleteAllNotificationsBody;

  /// No description provided for @notifDeleted.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigung gelöscht'**
  String get notifDeleted;

  /// No description provided for @allNotifsDeleted.
  ///
  /// In de, this message translates to:
  /// **'Alle Benachrichtigungen gelöscht'**
  String get allNotifsDeleted;

  /// No description provided for @notifDeleteError.
  ///
  /// In de, this message translates to:
  /// **'Benachrichtigung konnte nicht gelöscht werden.'**
  String get notifDeleteError;

  /// No description provided for @undo.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get undo;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
