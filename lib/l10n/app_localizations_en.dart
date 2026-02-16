// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tabTeams => 'Teams';

  @override
  String get tabGames => 'Games';

  @override
  String get tabProfile => 'Profile';

  @override
  String get profileTitle => 'Profile';

  @override
  String get anonymousPlayer => 'Anonymous Player';

  @override
  String get notLoggedIn => 'Not logged in';

  @override
  String get loggedIn => 'Logged in';

  @override
  String get pushNotifications => 'Push Notifications';

  @override
  String get pushToggleSubtitle => 'Toggle all push notifications';

  @override
  String get individualNotifications => 'Individual Notifications';

  @override
  String get pushInfoBanner =>
      'Push notifications will be activated soon. Your settings are already being saved.';

  @override
  String get createAccountHint =>
      'Create an account to make your own teams and secure your profile.';

  @override
  String get registerLogin => 'Register / Log in';

  @override
  String get logout => 'Log out';

  @override
  String get appVersion => 'Lineup · v1.0.0';

  @override
  String get prefsLoadError => 'Settings could not be loaded.';

  @override
  String get prefsSaveError => 'Settings could not be saved.';

  @override
  String get languageTitle => 'Language';

  @override
  String get german => 'Deutsch';

  @override
  String get english => 'English';

  @override
  String get myTeams => 'My Teams';

  @override
  String get notifications => 'Notifications';

  @override
  String get howItWorks => 'How it works';

  @override
  String get guideStep1 => 'Create your team using the + at the bottom right.';

  @override
  String get guideStep2 => 'Add players – with name and optional ranking.';

  @override
  String get guideStep3 => 'Share the invite link via WhatsApp.';

  @override
  String get guideStep4 =>
      'Players open the link and assign themselves to their name.';

  @override
  String get guideStep5 => 'As captain you can see who is already connected.';

  @override
  String get guideStep6 => 'Create matches – the lineup is sorted by ranking.';

  @override
  String welcomeTitle(String appName) {
    return 'Welcome to $appName';
  }

  @override
  String get welcomeSubtitle => 'Create your first team and invite players.';

  @override
  String get understood => 'Got it';

  @override
  String get accountRequired => 'Account required';

  @override
  String get accountRequiredBody =>
      'You need an account to create your own teams. Please register or log in.';

  @override
  String get cancel => 'Cancel';

  @override
  String get deleteTeamTitle => 'Delete team?';

  @override
  String deleteTeamBody(String teamName) {
    return 'Do you want to permanently delete \"$teamName\"? This cannot be undone.';
  }

  @override
  String get delete => 'Delete';

  @override
  String teamDeleted(String teamName) {
    return 'Team \"$teamName\" deleted';
  }

  @override
  String get teamDeleteError => 'Team could not be deleted.';

  @override
  String get removeTeamTitle => 'Remove team?';

  @override
  String removeTeamBody(String teamName) {
    return 'You are removing \"$teamName\" from your list only. The team remains for the captain and other members.';
  }

  @override
  String get remove => 'Remove';

  @override
  String teamRemoved(String teamName) {
    return 'Team \"$teamName\" removed';
  }

  @override
  String get teamRemoveError => 'Team could not be removed.';

  @override
  String get ownTeams => 'My Teams';

  @override
  String get sharedTeams => 'Shared Teams';

  @override
  String get connectionError => 'Connection problem';

  @override
  String get dataLoadError => 'Data could not be loaded.';

  @override
  String get tryAgain => 'Try again';

  @override
  String season(String year) {
    return 'Season $year';
  }

  @override
  String get gamesTitle => 'Games';

  @override
  String get refresh => 'Refresh';

  @override
  String get noGamesYet => 'No games yet';

  @override
  String get noGamesSubtitle => 'Create your first match in a team.';

  @override
  String get home => 'Home';

  @override
  String get away => 'Away';

  @override
  String get authWelcome => 'Welcome';

  @override
  String get authSubtitle => 'Your team. Your matches.';

  @override
  String get login => 'Log in';

  @override
  String get register => 'Register';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get passwordHint => 'Min. 8 characters with at least 1 number';

  @override
  String get passwordMinLength => 'At least 8 characters';

  @override
  String get passwordNeedsNumber => 'At least 1 number required';

  @override
  String get invalidEmail => 'Please enter a valid email address.';

  @override
  String get enterPassword => 'Please enter a password.';

  @override
  String get passwordsMismatch => 'Passwords do not match.';

  @override
  String get loginFailed => 'Login failed. Please try again.';

  @override
  String get registerFailed => 'Registration failed. Please try again.';

  @override
  String get invalidCredentials => 'Invalid email or password.';

  @override
  String get emailNotConfirmed =>
      'Email not yet confirmed. Please check your inbox.';

  @override
  String get emailAlreadyRegistered =>
      'This email is already registered. Please log in.';

  @override
  String get rateLimited => 'Too many attempts. Please wait a moment.';

  @override
  String errorPrefix(String message) {
    return 'Error: $message';
  }

  @override
  String get verificationPendingTitle => 'Check your email';

  @override
  String get verificationPendingBody =>
      'If an account with this email exists, we’ve sent you a confirmation email. Please check your inbox and spam folder.';

  @override
  String get resendConfirmationEmail => 'Resend confirmation email';

  @override
  String get resendEmailSuccess => 'Email sent (if the address is eligible).';

  @override
  String get resendEmailRateLimit => 'Please wait a few minutes and try again.';

  @override
  String get alreadyHaveAccountLogin => 'Already have an account? Log in';

  @override
  String get save => 'Save';

  @override
  String get matchDetails => 'Match Details';

  @override
  String get opponent => 'Opponent *';

  @override
  String get opponentHint => 'e.g. TC Zurich';

  @override
  String get pleaseComplete => 'Please fill in';

  @override
  String get dateAndTime => 'Date & Time';

  @override
  String get chooseDate => 'Choose date';

  @override
  String get chooseTime => 'Choose time';

  @override
  String get homeGame => 'Home game';

  @override
  String get awayGame => 'Away game';

  @override
  String get details => 'Details';

  @override
  String get location => 'Location';

  @override
  String get locationHint => 'e.g. Tennis Club Bern, Court 3';

  @override
  String get noteOptional => 'Note (optional)';

  @override
  String get noteHint => 'e.g. Meeting point 09:30';

  @override
  String get chooseDateAndTime => 'Please choose date and time';

  @override
  String get editMatch => 'Edit match';

  @override
  String get addMatch => 'Add match';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get createMatch => 'Create match';

  @override
  String get matchUpdated => 'Match updated';

  @override
  String get matchCreated => 'Match created';

  @override
  String get matchCreateError =>
      'Match could not be created. Please try again.';

  @override
  String get lineupPublished => 'Lineup published';

  @override
  String get replacementPromoted => 'Replacement promoted';

  @override
  String get noReserveAvailable => 'No reserve available';

  @override
  String get accountSectionTitle => 'Account';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountTitle => 'Delete account?';

  @override
  String get deleteAccountBody =>
      'Your account and all associated data will be permanently deleted. This action cannot be undone.';

  @override
  String typeToConfirm(String confirmWord) {
    return 'Type \"$confirmWord\" to confirm';
  }

  @override
  String get confirmWordDelete => 'DELETE';

  @override
  String get deleting => 'Deleting…';

  @override
  String get accountDeleted => 'Account deleted';

  @override
  String get accountDeleteError =>
      'Account could not be deleted. Please try again.';

  @override
  String get teamDetailTabOverview => 'Overview';

  @override
  String get teamDetailTabTeam => 'Team';

  @override
  String get teamDetailTabMatches => 'Matches';

  @override
  String get teamInfoBadge => 'Team Info';

  @override
  String get teamInfoTeam => 'Team';

  @override
  String get teamInfoClub => 'Club';

  @override
  String get teamInfoLeague => 'League';

  @override
  String get teamInfoSeason => 'Season';

  @override
  String get teamInfoCaptain => 'Captain';

  @override
  String get nextMatch => 'Next match';

  @override
  String get playersLabel => 'Players';

  @override
  String get connectedLabel => 'Connected';

  @override
  String get captainPlaysTitle => 'I play myself';

  @override
  String get captainPlaysSubtitle =>
      'Enable this if you also play as captain and want to appear in the lineup.';

  @override
  String get inviteLinkTitle => 'Invite link';

  @override
  String get inviteLinkDescription =>
      'Share the invite link so players can join the team.';

  @override
  String get shareLink => 'Share link';

  @override
  String get inviteLinkCreated => 'Invite link created';

  @override
  String get inviteLinkError => 'Invite link could not be created.';

  @override
  String get shareInviteTooltip => 'Share invite link';

  @override
  String get shareSubject => 'Lineup Team Invite';

  @override
  String teamSectionCount(String count) {
    return 'Team ($count)';
  }

  @override
  String connectedPlayersTitle(String count) {
    return 'Connected players ($count)';
  }

  @override
  String get addPlayer => 'Add player';

  @override
  String get firstName => 'First name *';

  @override
  String get firstNameHint => 'Max';

  @override
  String get lastName => 'Last name *';

  @override
  String get lastNameHint => 'Smith';

  @override
  String get enterFirstAndLastName => 'Please enter first and last name.';

  @override
  String get selectRanking => 'Please select a ranking.';

  @override
  String get genericError => 'Something went wrong. Please try again.';

  @override
  String get addButton => 'Add';

  @override
  String get whatsYourName => 'What’s your name?';

  @override
  String get nicknamePrompt =>
      'Please enter your name so your team can recognize you.';

  @override
  String get yourTeamName => 'Your name in team';

  @override
  String get nicknameHint => 'e.g. Max, Sandro, Martin W.';

  @override
  String get minTwoChars => 'At least 2 characters';

  @override
  String get nicknameSaveError => 'Player could not be added.';

  @override
  String get nameSaved => 'Name saved';

  @override
  String get changeName => 'Change name';

  @override
  String get nameUpdated => 'Name updated';

  @override
  String get nameSaveError => 'Name could not be saved.';

  @override
  String get changeSaveError => 'Change could not be saved.';

  @override
  String get noPlayersYet => 'No players yet';

  @override
  String get noPlayersEmptyBody =>
      'No players yet.\nAdd players with name and ranking.';

  @override
  String get shareInviteSubtitle =>
      'Share the invite link so players can assign themselves.';

  @override
  String get noMatchesTeamSubtitle =>
      'Create a match so your team can respond.';

  @override
  String get chipOpen => 'Open';

  @override
  String get chipAssigned => 'Assigned';

  @override
  String get chipYou => 'You';

  @override
  String get chipConnected => 'Connected';

  @override
  String get chipCaptain => 'Captain';

  @override
  String get chipCaptainPlaying => 'Captain (playing)';

  @override
  String get chipPlayer => 'Player';

  @override
  String get changeAvatarTooltip => 'Change profile picture';

  @override
  String get claimSlotTooltip => 'Assign player slot';

  @override
  String get changeNameTooltip => 'Change name';

  @override
  String get actionError => 'Action could not be performed.';

  @override
  String get avatarUpdated => 'Profile picture updated';

  @override
  String get avatarUploadError => 'Image could not be uploaded.';

  @override
  String get storageSetupRequired => 'Storage setup required';

  @override
  String get storageSetupBody =>
      'The storage bucket \"profile-photos\" has not been created yet.\nPlease follow these steps:';

  @override
  String get storageStep1 => 'Supabase Dashboard → Storage → \"New bucket\"';

  @override
  String get storageStep2 => 'Name exactly: profile-photos';

  @override
  String get storageStep3 => 'Public: OFF (private)';

  @override
  String get storageStep4 => 'SQL Editor → run the policies below';

  @override
  String get sqlCopied => 'SQL copied to clipboard';

  @override
  String get copySql => 'Copy SQL';

  @override
  String get closeButton => 'Close';

  @override
  String get notificationsTooltip => 'Notifications';

  @override
  String get removePlayer => 'Remove';

  @override
  String get matchTabOverview => 'Overview';

  @override
  String get matchTabLineup => 'Lineup';

  @override
  String get matchTabMore => 'More';

  @override
  String get editLabel => 'Edit';

  @override
  String matchConfirmedProgress(String yes, String total) {
    return '$yes of $total confirmed';
  }

  @override
  String get myAvailability => 'My availability';

  @override
  String get availYes => 'Confirmed';

  @override
  String get availNo => 'Declined';

  @override
  String get availMaybe => 'Maybe';

  @override
  String get availNoResponse => 'No response';

  @override
  String get availabilitiesTitle => 'Availabilities';

  @override
  String respondedProgress(String responded, String total) {
    return '$responded of $total responded';
  }

  @override
  String get playerAvailabilities => 'Player availabilities';

  @override
  String get subRequestSection => 'Substitution';

  @override
  String get noSubRequests =>
      'No substitute requests. For declines you can request a substitute here.';

  @override
  String get generateLineupTitle => 'Generate lineup';

  @override
  String get generateButton => 'Generate';

  @override
  String get lineupGenerateDescription =>
      'The lineup will be generated based on rankings and availabilities.\nYou can swap manually afterwards.\n\nAn existing lineup will be overwritten.';

  @override
  String get starterLabel => 'Starters';

  @override
  String get reserveLabel => 'Reserves';

  @override
  String get includeMaybeTitle => 'Include maybes';

  @override
  String get includeMaybeSubtitle =>
      'Players with \"Maybe\" will be added to fill spots.';

  @override
  String lineupCreatedToast(String starters, String reserves) {
    return 'Lineup created: $starters starters, $reserves reserves';
  }

  @override
  String get lineupTitle => 'Lineup';

  @override
  String get lineupStatusDraft => 'Draft';

  @override
  String get lineupStatusPublished => 'Published';

  @override
  String get allSlotsOccupied => 'All slots occupied';

  @override
  String get slotsFreeSingle => '1 slot available';

  @override
  String slotsFree(String count) {
    return '$count slots available';
  }

  @override
  String get regenerateButton => 'Regenerate';

  @override
  String get noLineupYet => 'No lineup yet.';

  @override
  String get noLineupYetAdmin =>
      'No lineup yet.\nTap \"Generate\" to create one.';

  @override
  String get captainCreatingLineup => 'Captain is creating the lineup …';

  @override
  String get subChainActive =>
      'Sub chain active: When a player declines, the next reserve is promoted automatically.';

  @override
  String starterCountHeader(String count) {
    return 'Starters ($count)';
  }

  @override
  String reserveCountHeader(String count) {
    return 'Reserves ($count)';
  }

  @override
  String get sendLineupToTeam => 'Send to team';

  @override
  String get lineupPublishedBanner =>
      'Lineup published. Declines trigger automatic promotion.';

  @override
  String get youStarter => 'You · Starter';

  @override
  String get youReserve => 'You · Reserve';

  @override
  String get publishLineupTitle => 'Publish lineup?';

  @override
  String get publishSendButton => 'Send';

  @override
  String get publishLineupBody =>
      'All team members will be notified about the lineup (in-app + push).';

  @override
  String get publishLineupConfirm => 'Do you want to send the lineup now?';

  @override
  String lineupPublishedToast(String recipients) {
    return 'Lineup published – $recipients notifications sent';
  }

  @override
  String get violationSingle => '⚠️ 1 rule violation detected';

  @override
  String violationMultiple(String count) {
    return '⚠️ $count rule violations detected';
  }

  @override
  String violationMore(String count) {
    return '… and $count more';
  }

  @override
  String get publishAnyway => 'Publishing still possible.';

  @override
  String get lineupPublishedNoReorder =>
      'Lineup is published – order can no longer be changed.';

  @override
  String get lineupBeingGenerated => 'Generating lineup …';

  @override
  String get lineupBeingPublished => 'Publishing lineup …';

  @override
  String get reorderNotPossible => 'Reordering is not possible right now.';

  @override
  String get deleteMatchTitle => 'Delete match?';

  @override
  String deleteMatchBody(String opponent) {
    return 'Do you really want to delete the match vs \"$opponent\"?\n\nAll availabilities and lineups will be lost.';
  }

  @override
  String get matchDeleted => 'Match deleted';

  @override
  String subRequestSentToast(String name) {
    return 'Substitute request sent to $name';
  }

  @override
  String get noSubAvailable => 'No available substitute found.';

  @override
  String get subRequestAcceptedToast => 'Substitute request accepted';

  @override
  String get subRequestDeclinedToast => 'Substitute request declined';

  @override
  String get somethingWentWrong => 'Something went wrong.';

  @override
  String get subRequestsTitle => 'Substitute requests';

  @override
  String pendingCountChip(String count) {
    return '$count pending';
  }

  @override
  String get pendingRequestsLabel => 'Pending requests';

  @override
  String get youWereAsked => 'You were asked:';

  @override
  String subForPlayer(String name) {
    return 'Substitute for $name';
  }

  @override
  String get canYouStepIn => 'Can you step in?';

  @override
  String get timeExpired => 'Time expired';

  @override
  String get acceptTooltip => 'Accept';

  @override
  String get declineTooltip => 'Decline';

  @override
  String get requestHistory => 'Request history:';

  @override
  String subForPlayerHistory(String subName, String originalName) {
    return '$subName for $originalName';
  }

  @override
  String get chipWaiting => 'Waiting for response';

  @override
  String get chipAccepted => 'Accepted';

  @override
  String get chipDeclined => 'Declined';

  @override
  String get subButton => 'Sub';

  @override
  String get sectionRides => 'Rides';

  @override
  String get carpoolsTitle => 'Carpools';

  @override
  String get iDriveButton => 'I\'m driving';

  @override
  String get noCarpoolsYet => 'No carpools yet.';

  @override
  String get noCarpoolsHint => 'No carpools yet. Offer a ride.';

  @override
  String get youSuffix => '(you)';

  @override
  String get joinRideButton => 'Join ride';

  @override
  String get leaveRideButton => 'Leave ride';

  @override
  String get joinedRideToast => 'You joined the ride';

  @override
  String get joinRideError => 'Could not save ride.';

  @override
  String get leftRideToast => 'Left the ride';

  @override
  String get leaveRideError => 'Could not save leaving.';

  @override
  String get deleteCarpoolTitle => 'Delete carpool?';

  @override
  String get deleteCarpoolBody => 'All passengers will be removed.';

  @override
  String get editCarpoolTitle => 'Edit carpool';

  @override
  String get seatsQuestion => 'How many seats do you offer?';

  @override
  String get departureLocationLabel => 'Departure location';

  @override
  String get departureLocationHint => 'e.g. Bern station';

  @override
  String departureTimeWithValue(String time) {
    return 'Departure: $time';
  }

  @override
  String get departureTimeOptional => 'Departure time (optional)';

  @override
  String get changeTooltip => 'Change';

  @override
  String get setTooltip => 'Set';

  @override
  String get removeTooltipLabel => 'Remove';

  @override
  String get carpoolNoteHint => 'e.g. Meeting point parking lot';

  @override
  String get carpoolSavedToast => 'Carpool saved';

  @override
  String get carpoolCreatedReloadToast =>
      'Carpool created. Please reload the page.';

  @override
  String departAtFormat(String date, String time) {
    return '$date at $time';
  }

  @override
  String get sectionDinner => 'Dinner';

  @override
  String answeredOfTotal(String answered, String total) {
    return '$answered of $total';
  }

  @override
  String get yourRsvp => 'Your RSVP';

  @override
  String get dinnerYes => 'Yes';

  @override
  String get dinnerNo => 'No';

  @override
  String get dinnerMaybe => 'Maybe';

  @override
  String get dinnerNoteHint => 'Note (e.g. \"arriving late\")';

  @override
  String get dinnerSaveError => 'Could not save. Please try again.';

  @override
  String get participantsTitle => 'Participants';

  @override
  String get sectionExpenses => 'Expenses';

  @override
  String get expenseTotal => 'Total';

  @override
  String perPersonLabel(String count) {
    return 'Per person ($count pers.)';
  }

  @override
  String get paidLabel => 'Paid';

  @override
  String get firstConfirmDinner =>
      'First confirm under \"Dinner\" before expenses can be recorded.';

  @override
  String get addExpenseButton => 'Add expense';

  @override
  String get noExpensesYet => 'No expenses recorded yet. Add a new expense.';

  @override
  String get noExpensesPossible =>
      'No expenses possible yet. First confirm under \"Dinner\".';

  @override
  String paidByLabel(String name) {
    return 'Paid by $name';
  }

  @override
  String perPersonAmountLabel(String amount) {
    return '$amount/pers.';
  }

  @override
  String paidOfShareCount(String paid, String total) {
    return '$paid/$total paid';
  }

  @override
  String get sharePaid => 'Paid';

  @override
  String get shareOpen => 'Open';

  @override
  String get deleteExpenseTooltip => 'Delete expense';

  @override
  String get markedAsPaid => 'Marked as paid';

  @override
  String get markedAsOpen => 'Marked as open';

  @override
  String get expenseTitleField => 'Title *';

  @override
  String get expenseTitleHint => 'e.g. Pizza, drinks';

  @override
  String get expenseAmountField => 'Amount (CHF) *';

  @override
  String get expenseAmountHint => 'e.g. 45.50';

  @override
  String get currencyPrefix => 'CHF ';

  @override
  String get expenseNoteHint => 'e.g. Restaurant Adler';

  @override
  String expenseDistribution(String count) {
    return 'Will be split equally among all $count dinner attendees (Yes).';
  }

  @override
  String get enterTitleValidation => 'Please enter a title.';

  @override
  String get enterAmountValidation => 'Please enter a valid amount.';

  @override
  String expenseCreatedToast(String title, String amount) {
    return 'Expense \"$title\" (CHF $amount) created';
  }

  @override
  String get deleteExpenseTitle => 'Delete expense?';

  @override
  String deleteExpenseBody(String title, String amount) {
    return '\"$title\" ($amount) and all shares will be deleted.';
  }

  @override
  String expenseDeletedToast(String title) {
    return 'Expense \"$title\" deleted';
  }

  @override
  String get roleCaptainSuffix => ' (Captain)';

  @override
  String get unknownPlayer => 'Unknown';

  @override
  String get lineupReorderHint => 'Hold ☰ and drag to swap positions';

  @override
  String get claimConfirmTitle => 'Confirm player';

  @override
  String get claimConfirmCta => 'Yes, that\'s me';

  @override
  String claimConfirmBody(String label) {
    return 'Are you \"$label\"?';
  }

  @override
  String claimWelcomeToast(String name) {
    return 'Welcome, $name!';
  }

  @override
  String get claimWhoAreYou => 'Who are you?';

  @override
  String get commonSkip => 'Skip';

  @override
  String get claimPickName =>
      'Select your name from the list\nso the team can assign you.';

  @override
  String get claimSearchHint => 'Search name…';

  @override
  String get claimNoSlotTitle => 'No open slot';

  @override
  String get claimNoSlotBody =>
      'Your captain hasn\'t added any players yet\nor all slots are already taken.';

  @override
  String get notifLoadError => 'Couldn\'t load notifications.';

  @override
  String get matchLoadError => 'Couldn\'t load match.';

  @override
  String notifTitleWithCount(String count) {
    return 'Notifications ($count)';
  }

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get allReadTitle => 'All read';

  @override
  String get allReadSubtitle =>
      'New notifications will appear here automatically.';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(String minutes) {
    return '$minutes min ago';
  }

  @override
  String timeHoursAgo(String hours) {
    return '${hours}h ago';
  }

  @override
  String timeDaysAgo(String days) {
    return '${days}d ago';
  }

  @override
  String get forgotPasswordAppBar => 'Forgot password';

  @override
  String get resetPasswordTitle => 'Reset password';

  @override
  String get resetPasswordInstructions =>
      'Enter your email address and we\'ll send you a reset link.';

  @override
  String get emailSentTitle => 'Email sent!';

  @override
  String get resetPasswordSentBody =>
      'Check your inbox and click the link to set a new password.';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get sendLinkButton => 'Send link';

  @override
  String get emailSendError => 'Couldn\'t send email.';

  @override
  String get sportSelectionTitle => 'Choose sport';

  @override
  String get sportSelectionSubtitle => 'What sport does your team play?';

  @override
  String get eventsLoadError => 'Couldn\'t load events.';

  @override
  String get matchUnavailableDeleted =>
      'Match unavailable (deleted or archived).';

  @override
  String get matchUnavailable => 'Match unavailable.';

  @override
  String get noNewEvents => 'No new events';

  @override
  String get noNewEventsSubtitle => 'When there\'s news, you\'ll see it here.';

  @override
  String get teamFilterLabel => 'Team filter';

  @override
  String get allTeams => 'All teams';

  @override
  String get createTeamTitle => 'Create team';

  @override
  String get teamNameLabel => 'Club Name / Team Name *';

  @override
  String get teamNameHint => 'e.g. TC Winterthur 1';

  @override
  String get leagueLabel => 'League (optional)';

  @override
  String get leagueHint => 'e.g. 3rd League Men';

  @override
  String get seasonYearLabel => 'Season year';

  @override
  String get captainNameRequired => 'Your name in team *';

  @override
  String get captainNamePrompt => 'Your name, so your team recognizes you.';

  @override
  String get createTeamPlaysSelfSubtitle =>
      'Enable this if you also play as captain.';

  @override
  String get createButton => 'Create';

  @override
  String get teamCreatedToast => 'Team created';

  @override
  String get teamCreateError => 'Couldn\'t create team. Please try again.';

  @override
  String get enterTeamName => 'Please enter team name.';

  @override
  String get enterCaptainName => 'Please enter your name (min. 2 characters).';

  @override
  String get invalidSeasonYear => 'Please enter a valid season year.';

  @override
  String get selectRankingError => 'Please select ranking.';

  @override
  String get countryLabel => 'Country *';

  @override
  String get rankingLabelRequired => 'Ranking *';

  @override
  String get rankingAvailableSection => 'Available';

  @override
  String get dropdownHint => 'Please select';

  @override
  String get notifTitleLineup => 'Lineup';

  @override
  String get notifTitleSubRequest => 'Sub request';

  @override
  String get notifTitlePromotion => 'Promoted';

  @override
  String get notifTitleAutoPromotion => 'Auto-promotion';

  @override
  String get notifTitleLineupGenerated => 'Lineup generated';

  @override
  String get notifTitleConfirmation => 'Confirmation';

  @override
  String get notifTitleWarning => 'Warning';

  @override
  String get notifTitlePromoted => 'Promotion';

  @override
  String get notifBodyLineupOnline => 'The lineup is online. Check it out!';

  @override
  String notifBodySelectedAs(String role, String position) {
    return 'You were placed as $role (Pos. $position)';
  }

  @override
  String notifBodyReserveConfirm(String position) {
    return 'You are reserve $position. Please confirm.';
  }

  @override
  String notifBodyPromotedToStarter(String position) {
    return 'You were promoted to starter (Pos. $position) 🎉';
  }

  @override
  String get notifBodyAutoPromoted =>
      'You were promoted as reserve and are now playing 🎉';

  @override
  String notifBodyAutoPromotionCaptain(String inName, String outName) {
    return 'Auto-promotion: $inName replaces $outName';
  }

  @override
  String notifBodyNoReserve(String absent) {
    return '$absent declined – no reserve available!';
  }

  @override
  String notifBodyLineupCreated(String starters, String reserves) {
    return 'Lineup created: $starters starters, $reserves reserves';
  }

  @override
  String get notifBodyPlayerConfirmed => 'A player has confirmed';

  @override
  String get notifBodyNoReservesLeft => 'No more reserves available!';

  @override
  String notifBodyPromotedToPos(String position) {
    return 'You were promoted to starter (Pos. $position) 🎉';
  }

  @override
  String get notifBodyRosterChanged => 'The lineup has been changed';

  @override
  String get notifBodyNeedsResponse => 'Please confirm your lineup';

  @override
  String eventBodyReplaced(String inName, String outName) {
    return '$inName replaces $outName';
  }
}
