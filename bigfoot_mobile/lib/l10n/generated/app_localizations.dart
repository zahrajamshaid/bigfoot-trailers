import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Bigfoot Trailers'**
  String get appTitle;

  /// No description provided for @appTitleShort.
  ///
  /// In en, this message translates to:
  /// **'Bigfoot'**
  String get appTitleShort;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get commonLoading;

  /// No description provided for @commonDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// No description provided for @commonUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get commonUser;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get commonSet;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {msg}'**
  String commonFailed(String msg);

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get commonSubmit;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navTrailers.
  ///
  /// In en, this message translates to:
  /// **'Trailers'**
  String get navTrailers;

  /// No description provided for @navProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get navProduction;

  /// No description provided for @navQc.
  ///
  /// In en, this message translates to:
  /// **'QC'**
  String get navQc;

  /// No description provided for @navPayroll.
  ///
  /// In en, this message translates to:
  /// **'Payroll'**
  String get navPayroll;

  /// No description provided for @navDeliveries.
  ///
  /// In en, this message translates to:
  /// **'Deliveries'**
  String get navDeliveries;

  /// No description provided for @navAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get navAdmin;

  /// No description provided for @navMyQueue.
  ///
  /// In en, this message translates to:
  /// **'My Queue'**
  String get navMyQueue;

  /// No description provided for @navMyPoints.
  ///
  /// In en, this message translates to:
  /// **'My Points'**
  String get navMyPoints;

  /// No description provided for @navMyDeliveries.
  ///
  /// In en, this message translates to:
  /// **'My Deliveries'**
  String get navMyDeliveries;

  /// No description provided for @navHelp.
  ///
  /// In en, this message translates to:
  /// **'How to Use'**
  String get navHelp;

  /// No description provided for @connectionConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionConnected;

  /// No description provided for @connectionConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get connectionConnecting;

  /// No description provided for @connectionOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get connectionOffline;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Offline - real-time updates paused'**
  String get offlineBanner;

  /// No description provided for @backToExit.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get backToExit;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'BIGFOOT TRAILERS'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get loginSubtitle;

  /// No description provided for @loginEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get loginEmail;

  /// No description provided for @loginPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPassword;

  /// No description provided for @loginRememberEmail.
  ///
  /// In en, this message translates to:
  /// **'Remember email'**
  String get loginRememberEmail;

  /// No description provided for @loginSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginSignIn;

  /// No description provided for @loginPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get loginPasswordRequired;

  /// No description provided for @settingsConnectionSection.
  ///
  /// In en, this message translates to:
  /// **'CONNECTION'**
  String get settingsConnectionSection;

  /// No description provided for @settingsSecuritySection.
  ///
  /// In en, this message translates to:
  /// **'SECURITY'**
  String get settingsSecuritySection;

  /// No description provided for @settingsAboutSection.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get settingsAboutSection;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get settingsLanguageSection;

  /// No description provided for @settingsWebSocketStatus.
  ///
  /// In en, this message translates to:
  /// **'WebSocket Status'**
  String get settingsWebSocketStatus;

  /// No description provided for @settingsWebSocketSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real-time connection'**
  String get settingsWebSocketSubtitle;

  /// No description provided for @settingsPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Require PIN on App Open'**
  String get settingsPinTitle;

  /// No description provided for @settingsPinEnabled.
  ///
  /// In en, this message translates to:
  /// **'PIN lock is enabled'**
  String get settingsPinEnabled;

  /// No description provided for @settingsPinDisabled.
  ///
  /// In en, this message translates to:
  /// **'No PIN required'**
  String get settingsPinDisabled;

  /// No description provided for @settingsPinSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a 4-digit PIN'**
  String get settingsPinSetTitle;

  /// No description provided for @settingsPinSetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be asked for this PIN every time you open the app.'**
  String get settingsPinSetSubtitle;

  /// No description provided for @settingsPinConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get settingsPinConfirmTitle;

  /// No description provided for @settingsPinConfirmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-enter your PIN to confirm.'**
  String get settingsPinConfirmSubtitle;

  /// No description provided for @settingsPinMismatch.
  ///
  /// In en, this message translates to:
  /// **'PINs don\'t match. Try again.'**
  String get settingsPinMismatch;

  /// No description provided for @settingsPinDisableTitle.
  ///
  /// In en, this message translates to:
  /// **'Disable PIN lock'**
  String get settingsPinDisableTitle;

  /// No description provided for @settingsPinDisableSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your current PIN to turn lock off.'**
  String get settingsPinDisableSubtitle;

  /// No description provided for @settingsPinCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsPinCancel;

  /// No description provided for @settingsAppVersion.
  ///
  /// In en, this message translates to:
  /// **'App Version'**
  String get settingsAppVersion;

  /// No description provided for @settingsApiVersion.
  ///
  /// In en, this message translates to:
  /// **'API Version'**
  String get settingsApiVersion;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settingsLanguageSpanish;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get settingsSignOutConfirmTitle;

  /// No description provided for @settingsSignOutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out? You will need to sign in again.'**
  String get settingsSignOutConfirmMessage;

  /// No description provided for @dashboardGoodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get dashboardGoodMorning;

  /// No description provided for @dashboardGoodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get dashboardGoodAfternoon;

  /// No description provided for @dashboardGoodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get dashboardGoodEvening;

  /// No description provided for @authPinTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get authPinTitle;

  /// No description provided for @authPinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your 4-digit PIN to unlock'**
  String get authPinSubtitle;

  /// No description provided for @authPinIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN'**
  String get authPinIncorrect;

  /// No description provided for @authPinSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out instead'**
  String get authPinSignOut;

  /// No description provided for @authSplashTagline.
  ///
  /// In en, this message translates to:
  /// **'Built to haul. Ready to move.'**
  String get authSplashTagline;

  /// No description provided for @dashStatActiveTrailers.
  ///
  /// In en, this message translates to:
  /// **'Active Trailers'**
  String get dashStatActiveTrailers;

  /// No description provided for @dashStatReadyForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Ready for Delivery'**
  String get dashStatReadyForDelivery;

  /// No description provided for @dashStatHotTrailers.
  ///
  /// In en, this message translates to:
  /// **'Hot Trailers'**
  String get dashStatHotTrailers;

  /// No description provided for @dashStatHotBadge.
  ///
  /// In en, this message translates to:
  /// **'HOT'**
  String get dashStatHotBadge;

  /// No description provided for @dashStatStalledSteps.
  ///
  /// In en, this message translates to:
  /// **'Stalled Steps'**
  String get dashStatStalledSteps;

  /// No description provided for @dashStatCompletedThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Completed This Week'**
  String get dashStatCompletedThisWeek;

  /// No description provided for @dashStatQcFailRate.
  ///
  /// In en, this message translates to:
  /// **'QC Fail Rate'**
  String get dashStatQcFailRate;

  /// No description provided for @dashStatPointsToday.
  ///
  /// In en, this message translates to:
  /// **'Points Today'**
  String get dashStatPointsToday;

  /// No description provided for @dashStatPointsThisWeek.
  ///
  /// In en, this message translates to:
  /// **'Points This Week'**
  String get dashStatPointsThisWeek;

  /// No description provided for @dashStatNextTrailer.
  ///
  /// In en, this message translates to:
  /// **'Next Trailer'**
  String get dashStatNextTrailer;

  /// No description provided for @dashStatReadyForInspection.
  ///
  /// In en, this message translates to:
  /// **'Ready for Inspection'**
  String get dashStatReadyForInspection;

  /// No description provided for @dashStatInspectionsToday.
  ///
  /// In en, this message translates to:
  /// **'Inspections Today'**
  String get dashStatInspectionsToday;

  /// No description provided for @dashStatFailRateToday.
  ///
  /// In en, this message translates to:
  /// **'Fail Rate Today'**
  String get dashStatFailRateToday;

  /// No description provided for @dashStatReworkQueue.
  ///
  /// In en, this message translates to:
  /// **'Rework Queue'**
  String get dashStatReworkQueue;

  /// No description provided for @dashStatScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get dashStatScheduled;

  /// No description provided for @dashStatReadyForPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready for Pickup'**
  String get dashStatReadyForPickup;

  /// No description provided for @dashStockInventory.
  ///
  /// In en, this message translates to:
  /// **'Stock Inventory'**
  String get dashStockInventory;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusInProduction.
  ///
  /// In en, this message translates to:
  /// **'In Production'**
  String get statusInProduction;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusReady;

  /// No description provided for @statusInTransit.
  ///
  /// In en, this message translates to:
  /// **'In Transit'**
  String get statusInTransit;

  /// No description provided for @statusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get statusDelivered;

  /// No description provided for @statusOnHold.
  ///
  /// In en, this message translates to:
  /// **'On Hold'**
  String get statusOnHold;

  /// No description provided for @statusScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get statusScheduled;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @statusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get statusWaiting;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get statusComplete;

  /// No description provided for @statusRework.
  ///
  /// In en, this message translates to:
  /// **'Rework'**
  String get statusRework;

  /// No description provided for @saleStatusSold.
  ///
  /// In en, this message translates to:
  /// **'SOLD'**
  String get saleStatusSold;

  /// No description provided for @saleStatusSalePending.
  ///
  /// In en, this message translates to:
  /// **'SALE PENDING'**
  String get saleStatusSalePending;

  /// No description provided for @saleStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get saleStatusAvailable;

  /// No description provided for @saleStatusSoldLong.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get saleStatusSoldLong;

  /// No description provided for @saleStatusSalePendingLong.
  ///
  /// In en, this message translates to:
  /// **'Sale Pending'**
  String get saleStatusSalePendingLong;

  /// No description provided for @trailersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by SO# or customer...'**
  String get trailersSearchHint;

  /// No description provided for @trailersFilterHotOnly.
  ///
  /// In en, this message translates to:
  /// **'Hot Only'**
  String get trailersFilterHotOnly;

  /// No description provided for @trailersStockBuild.
  ///
  /// In en, this message translates to:
  /// **'Stock Build'**
  String get trailersStockBuild;

  /// No description provided for @trailersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No trailers found'**
  String get trailersEmpty;

  /// No description provided for @trailersStepIndicator.
  ///
  /// In en, this message translates to:
  /// **'Step {step}/{total} — {dept}'**
  String trailersStepIndicator(int step, int total, String dept);

  /// No description provided for @cacheBannerJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get cacheBannerJustNow;

  /// No description provided for @cacheBannerUnknownTime.
  ///
  /// In en, this message translates to:
  /// **'unknown time'**
  String get cacheBannerUnknownTime;

  /// No description provided for @cacheBannerMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute ago} other{{minutes} minutes ago}}'**
  String cacheBannerMinutesAgo(int minutes);

  /// No description provided for @cacheBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'Showing cached data. Last updated {when}.'**
  String cacheBannerMessage(String when);

  /// No description provided for @createTrailerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Trailer'**
  String get createTrailerTitle;

  /// No description provided for @createTrailerSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create Trailer'**
  String get createTrailerSubmit;

  /// No description provided for @createTrailerModelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No trailer models are configured on the server.'**
  String get createTrailerModelsEmpty;

  /// No description provided for @createTrailerModelsLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Could not load trailer models. Check your connection.'**
  String get createTrailerModelsLoadFail;

  /// No description provided for @createTrailerModelsNone.
  ///
  /// In en, this message translates to:
  /// **'No trailer models available.'**
  String get createTrailerModelsNone;

  /// No description provided for @createTrailerModelFallback.
  ///
  /// In en, this message translates to:
  /// **'Model {id}'**
  String createTrailerModelFallback(String id);

  /// No description provided for @createTrailerPickPdfFail.
  ///
  /// In en, this message translates to:
  /// **'Could not read the selected PDF file.'**
  String get createTrailerPickPdfFail;

  /// No description provided for @createTrailerPickerOpenFail.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the file picker.'**
  String get createTrailerPickerOpenFail;

  /// No description provided for @createTrailerStockDestRequired.
  ///
  /// In en, this message translates to:
  /// **'Pick a stock destination'**
  String get createTrailerStockDestRequired;

  /// No description provided for @createTrailerCreated.
  ///
  /// In en, this message translates to:
  /// **'Trailer {so} created with 12 workflow steps'**
  String createTrailerCreated(String so);

  /// No description provided for @createTrailerCreatedPdfWarn.
  ///
  /// In en, this message translates to:
  /// **'Trailer created. PDF upload failed: {warning}'**
  String createTrailerCreatedPdfWarn(String warning);

  /// No description provided for @createTrailerFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create trailer'**
  String get createTrailerFail;

  /// No description provided for @createTrailerPdfRetryLater.
  ///
  /// In en, this message translates to:
  /// **'no network — PDF will retry later'**
  String get createTrailerPdfRetryLater;

  /// No description provided for @createTrailerSoLabel.
  ///
  /// In en, this message translates to:
  /// **'SO Number *'**
  String get createTrailerSoLabel;

  /// No description provided for @createTrailerSoRequired.
  ///
  /// In en, this message translates to:
  /// **'SO number is required'**
  String get createTrailerSoRequired;

  /// No description provided for @createTrailerModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Trailer Model *'**
  String get createTrailerModelLabel;

  /// No description provided for @createTrailerModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a trailer model'**
  String get createTrailerModelRequired;

  /// No description provided for @createTrailerColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get createTrailerColorLabel;

  /// No description provided for @createTrailerSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size (ft)'**
  String get createTrailerSizeLabel;

  /// No description provided for @createTrailerNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Options / Notes'**
  String get createTrailerNotesLabel;

  /// No description provided for @trailerVinLabel.
  ///
  /// In en, this message translates to:
  /// **'VIN Number'**
  String get trailerVinLabel;

  /// No description provided for @trailerVinHint.
  ///
  /// In en, this message translates to:
  /// **'17 characters'**
  String get trailerVinHint;

  /// No description provided for @trailerVinInvalid.
  ///
  /// In en, this message translates to:
  /// **'VIN must be 17 characters (no I, O or Q)'**
  String get trailerVinInvalid;

  /// No description provided for @createTrailerSpecialLabel.
  ///
  /// In en, this message translates to:
  /// **'Special Note'**
  String get createTrailerSpecialLabel;

  /// No description provided for @createTrailerSpecialHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. ship empty, hold for inspection'**
  String get createTrailerSpecialHint;

  /// No description provided for @createTrailerStockBuild.
  ///
  /// In en, this message translates to:
  /// **'Stock Build'**
  String get createTrailerStockBuild;

  /// No description provided for @createTrailerStockBuildSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No customer assigned'**
  String get createTrailerStockBuildSubtitle;

  /// No description provided for @createTrailerCustomerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get createTrailerCustomerLabel;

  /// No description provided for @createTrailerCustomerHint.
  ///
  /// In en, this message translates to:
  /// **'Buyer name — leave blank for stock'**
  String get createTrailerCustomerHint;

  /// No description provided for @createTrailerCustomerHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional. A trailer with a customer is marked sold.'**
  String get createTrailerCustomerHelper;

  /// No description provided for @createTrailerStockDestLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock Destination *'**
  String get createTrailerStockDestLabel;

  /// No description provided for @createTrailerPdfSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'QB Sales Order PDF'**
  String get createTrailerPdfSectionTitle;

  /// No description provided for @createTrailerPdfRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove PDF'**
  String get createTrailerPdfRemoveTooltip;

  /// No description provided for @createTrailerPdfOptionalHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional — attach the QuickBooks SO PDF for this trailer.'**
  String get createTrailerPdfOptionalHelper;

  /// No description provided for @createTrailerPdfReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace PDF'**
  String get createTrailerPdfReplace;

  /// No description provided for @createTrailerPdfAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach PDF'**
  String get createTrailerPdfAttach;

  /// No description provided for @editTrailerTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {so}'**
  String editTrailerTitle(String so);

  /// No description provided for @editTrailerSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get editTrailerSubmit;

  /// No description provided for @editTrailerUpdated.
  ///
  /// In en, this message translates to:
  /// **'Trailer {so} updated'**
  String editTrailerUpdated(String so);

  /// No description provided for @editTrailerUpdatedPdfWarn.
  ///
  /// In en, this message translates to:
  /// **'Trailer updated. PDF upload failed: {warning}'**
  String editTrailerUpdatedPdfWarn(String warning);

  /// No description provided for @editTrailerFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to update trailer'**
  String get editTrailerFail;

  /// No description provided for @editTrailerPdfDiscardTooltip.
  ///
  /// In en, this message translates to:
  /// **'Discard new PDF'**
  String get editTrailerPdfDiscardTooltip;

  /// No description provided for @editTrailerPdfExisting.
  ///
  /// In en, this message translates to:
  /// **'A PDF is already attached. Pick a new file to replace it.'**
  String get editTrailerPdfExisting;

  /// No description provided for @trailerDetailTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Trailer #{id}'**
  String trailerDetailTitleFallback(int id);

  /// No description provided for @trailerDetailMenuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Trailer'**
  String get trailerDetailMenuEdit;

  /// No description provided for @trailerDetailMenuRemoveHot.
  ///
  /// In en, this message translates to:
  /// **'Remove Hot'**
  String get trailerDetailMenuRemoveHot;

  /// No description provided for @trailerDetailMenuMarkHot.
  ///
  /// In en, this message translates to:
  /// **'Mark Hot'**
  String get trailerDetailMenuMarkHot;

  /// No description provided for @trailerDetailMenuSetPriority.
  ///
  /// In en, this message translates to:
  /// **'Set Priority'**
  String get trailerDetailMenuSetPriority;

  /// No description provided for @trailerDetailMenuAddAddon.
  ///
  /// In en, this message translates to:
  /// **'Add Addon'**
  String get trailerDetailMenuAddAddon;

  /// No description provided for @trailerDetailMenuViewPdf.
  ///
  /// In en, this message translates to:
  /// **'View QB PDF'**
  String get trailerDetailMenuViewPdf;

  /// No description provided for @trailerDetailMenuDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Trailer'**
  String get trailerDetailMenuDelete;

  /// No description provided for @trailerDetailTabInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get trailerDetailTabInfo;

  /// No description provided for @trailerDetailTabWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Workflow'**
  String get trailerDetailTabWorkflow;

  /// No description provided for @trailerDetailTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get trailerDetailTabHistory;

  /// No description provided for @trailerDetailTabPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get trailerDetailTabPhotos;

  /// No description provided for @trailerDetailDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete trailer?'**
  String get trailerDetailDeleteTitle;

  /// No description provided for @trailerDetailDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes {so} and ALL related records — production steps, QC inspections, deliveries, photos, addons, and history.\n\nThis cannot be undone.'**
  String trailerDetailDeleteBody(String so);

  /// No description provided for @trailerDetailDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get trailerDetailDeleteConfirm;

  /// No description provided for @trailerDetailDeleted.
  ///
  /// In en, this message translates to:
  /// **'{so} deleted'**
  String trailerDetailDeleted(String so);

  /// No description provided for @trailerDetailDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {msg}'**
  String trailerDetailDeleteFailed(String msg);

  /// No description provided for @trailerDetailPriorityTitle.
  ///
  /// In en, this message translates to:
  /// **'Set Priority'**
  String get trailerDetailPriorityTitle;

  /// No description provided for @trailerDetailPriorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority number'**
  String get trailerDetailPriorityLabel;

  /// No description provided for @trailerDetailPriorityHint.
  ///
  /// In en, this message translates to:
  /// **'1 = highest'**
  String get trailerDetailPriorityHint;

  /// No description provided for @trailerDetailPrioritySet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get trailerDetailPrioritySet;

  /// No description provided for @trailerDetailAddonTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Addon'**
  String get trailerDetailAddonTitle;

  /// No description provided for @trailerDetailAddonName.
  ///
  /// In en, this message translates to:
  /// **'Addon name *'**
  String get trailerDetailAddonName;

  /// No description provided for @trailerDetailAddonNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get trailerDetailAddonNotes;

  /// No description provided for @trailerDetailAddonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get trailerDetailAddonAdd;

  /// No description provided for @trailerDetailUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {msg}'**
  String trailerDetailUpdateFailed(String msg);

  /// No description provided for @trailerDetailMarkedSold.
  ///
  /// In en, this message translates to:
  /// **'Trailer marked as sold'**
  String get trailerDetailMarkedSold;

  /// No description provided for @trailerDetailMarkedSalePending.
  ///
  /// In en, this message translates to:
  /// **'Trailer marked as sale pending'**
  String get trailerDetailMarkedSalePending;

  /// No description provided for @trailerDetailMarkedAvailable.
  ///
  /// In en, this message translates to:
  /// **'Trailer marked as available'**
  String get trailerDetailMarkedAvailable;

  /// No description provided for @trailerDetailBannerSold.
  ///
  /// In en, this message translates to:
  /// **'SOLD'**
  String get trailerDetailBannerSold;

  /// No description provided for @trailerDetailBannerSalePending.
  ///
  /// In en, this message translates to:
  /// **'SALE PENDING'**
  String get trailerDetailBannerSalePending;

  /// No description provided for @trailerDetailBannerAvailable.
  ///
  /// In en, this message translates to:
  /// **'AVAILABLE'**
  String get trailerDetailBannerAvailable;

  /// No description provided for @trailerDetailSoldTo.
  ///
  /// In en, this message translates to:
  /// **'Sold to {buyer}'**
  String trailerDetailSoldTo(String buyer);

  /// No description provided for @trailerDetailMarkedSoldShort.
  ///
  /// In en, this message translates to:
  /// **'Marked sold'**
  String get trailerDetailMarkedSoldShort;

  /// No description provided for @trailerDetailSalePendingDesc.
  ///
  /// In en, this message translates to:
  /// **'A sale is in progress for this trailer'**
  String get trailerDetailSalePendingDesc;

  /// No description provided for @trailerDetailAvailableDesc.
  ///
  /// In en, this message translates to:
  /// **'Not yet sold — available for a customer'**
  String get trailerDetailAvailableDesc;

  /// No description provided for @trailerDetailMarkAvailable.
  ///
  /// In en, this message translates to:
  /// **'Mark Available'**
  String get trailerDetailMarkAvailable;

  /// No description provided for @trailerDetailAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get trailerDetailAvailable;

  /// No description provided for @trailerDetailSalePending.
  ///
  /// In en, this message translates to:
  /// **'Sale Pending'**
  String get trailerDetailSalePending;

  /// No description provided for @trailerDetailSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get trailerDetailSold;

  /// No description provided for @trailerDetailMarkSoldTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark {so} as sold'**
  String trailerDetailMarkSoldTitle(String so);

  /// No description provided for @trailerDetailMarkSoldBuyerRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the buyer\'s name'**
  String get trailerDetailMarkSoldBuyerRequired;

  /// No description provided for @trailerDetailMarkSoldBuyerLabel.
  ///
  /// In en, this message translates to:
  /// **'Buyer name *'**
  String get trailerDetailMarkSoldBuyerLabel;

  /// No description provided for @trailerDetailMarkSoldBuyerHint.
  ///
  /// In en, this message translates to:
  /// **'Who bought this trailer?'**
  String get trailerDetailMarkSoldBuyerHint;

  /// No description provided for @trailerDetailMarkSoldButton.
  ///
  /// In en, this message translates to:
  /// **'Mark Sold'**
  String get trailerDetailMarkSoldButton;

  /// No description provided for @trailerDetailUnknownModel.
  ///
  /// In en, this message translates to:
  /// **'Unknown Model'**
  String get trailerDetailUnknownModel;

  /// No description provided for @trailerDetailNoCustomer.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get trailerDetailNoCustomer;

  /// No description provided for @trailerDetailFieldCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get trailerDetailFieldCustomer;

  /// No description provided for @trailerDetailFieldColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get trailerDetailFieldColor;

  /// No description provided for @trailerDetailFieldSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get trailerDetailFieldSize;

  /// No description provided for @trailerDetailFieldPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get trailerDetailFieldPriority;

  /// No description provided for @trailerDetailPriorityDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get trailerDetailPriorityDefault;

  /// No description provided for @trailerDetailOpenPdf.
  ///
  /// In en, this message translates to:
  /// **'Open QB PDF'**
  String get trailerDetailOpenPdf;

  /// No description provided for @trailerDetailNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Options / Notes'**
  String get trailerDetailNotesLabel;

  /// No description provided for @trailerDetailSpecialLabel.
  ///
  /// In en, this message translates to:
  /// **'Special Note'**
  String get trailerDetailSpecialLabel;

  /// No description provided for @trailerDetailAddonsTitle.
  ///
  /// In en, this message translates to:
  /// **'Addons'**
  String get trailerDetailAddonsTitle;

  /// No description provided for @trailerDetailDepartmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get trailerDetailDepartmentLabel;

  /// No description provided for @trailerDetailLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get trailerDetailLocationLabel;

  /// No description provided for @trailerDetailStatusReadyForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Ready for delivery'**
  String get trailerDetailStatusReadyForDelivery;

  /// No description provided for @trailerDetailStatusInTransit.
  ///
  /// In en, this message translates to:
  /// **'In transit'**
  String get trailerDetailStatusInTransit;

  /// No description provided for @trailerDetailStatusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get trailerDetailStatusDelivered;

  /// No description provided for @trailerDetailStatusOnHold.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get trailerDetailStatusOnHold;

  /// No description provided for @trailerDetailStatusPendingProduction.
  ///
  /// In en, this message translates to:
  /// **'Pending production'**
  String get trailerDetailStatusPendingProduction;

  /// No description provided for @trailerDetailStatusWorkflowComplete.
  ///
  /// In en, this message translates to:
  /// **'Workflow complete'**
  String get trailerDetailStatusWorkflowComplete;

  /// No description provided for @trailerDetailNoSteps.
  ///
  /// In en, this message translates to:
  /// **'No workflow steps'**
  String get trailerDetailNoSteps;

  /// No description provided for @trailerDetailJumpTitle.
  ///
  /// In en, this message translates to:
  /// **'Move trailer to step {n}?'**
  String trailerDetailJumpTitle(int n);

  /// No description provided for @trailerDetailJumpBody.
  ///
  /// In en, this message translates to:
  /// **'This places the trailer at \"{dept}\" as the current active step.\n\n• Earlier steps will be marked complete (no points awarded for any that weren\'t already done).\n• Later steps will be reset to waiting.\n• Each rolled-back step is recorded in the history tab.'**
  String trailerDetailJumpBody(String dept);

  /// No description provided for @trailerDetailJumpReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get trailerDetailJumpReasonLabel;

  /// No description provided for @trailerDetailJumpReasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. wrong step tapped earlier'**
  String get trailerDetailJumpReasonHint;

  /// No description provided for @trailerDetailJumpConfirm.
  ///
  /// In en, this message translates to:
  /// **'Move Here'**
  String get trailerDetailJumpConfirm;

  /// No description provided for @trailerDetailJumpedTo.
  ///
  /// In en, this message translates to:
  /// **'Trailer moved to \"{dept}\"'**
  String trailerDetailJumpedTo(String dept);

  /// No description provided for @trailerDetailJumpFailed.
  ///
  /// In en, this message translates to:
  /// **'Move failed: {msg}'**
  String trailerDetailJumpFailed(String msg);

  /// No description provided for @trailerDetailCurrentlyActive.
  ///
  /// In en, this message translates to:
  /// **'Currently active'**
  String get trailerDetailCurrentlyActive;

  /// No description provided for @trailerDetailMoveBackHere.
  ///
  /// In en, this message translates to:
  /// **'Move trailer back here'**
  String get trailerDetailMoveBackHere;

  /// No description provided for @trailerDetailMoveHere.
  ///
  /// In en, this message translates to:
  /// **'Move trailer here'**
  String get trailerDetailMoveHere;

  /// No description provided for @trailerDetailNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get trailerDetailNoHistory;

  /// No description provided for @trailerDetailNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No stage photos available'**
  String get trailerDetailNoPhotos;

  /// No description provided for @trailerDetailReworkBadge.
  ///
  /// In en, this message translates to:
  /// **'REWORK x{count}'**
  String trailerDetailReworkBadge(int count);

  /// No description provided for @trailerDetailCompletedOn.
  ///
  /// In en, this message translates to:
  /// **'Completed {when}'**
  String trailerDetailCompletedOn(String when);

  /// No description provided for @trailerDetailPointsAwarded.
  ///
  /// In en, this message translates to:
  /// **'+{pts} pts'**
  String trailerDetailPointsAwarded(String pts);

  /// No description provided for @trailerDetailStepLabel.
  ///
  /// In en, this message translates to:
  /// **'Step {n}'**
  String trailerDetailStepLabel(int n);

  /// No description provided for @trailerDetailPriorityBadge.
  ///
  /// In en, this message translates to:
  /// **'#{n}'**
  String trailerDetailPriorityBadge(int n);

  /// No description provided for @queueLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading queue...'**
  String get queueLoading;

  /// No description provided for @queueDepartmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get queueDepartmentLabel;

  /// No description provided for @queueTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueTitleFallback;

  /// No description provided for @queueFilterStalled.
  ///
  /// In en, this message translates to:
  /// **'Stalled'**
  String get queueFilterStalled;

  /// No description provided for @queueFilterStalledCount.
  ///
  /// In en, this message translates to:
  /// **'Stalled ({n})'**
  String queueFilterStalledCount(int n);

  /// No description provided for @queueTrailerCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trailer} other{{count} trailers}}'**
  String queueTrailerCount(int count);

  /// No description provided for @queueUndoTitle.
  ///
  /// In en, this message translates to:
  /// **'Undo Completion?'**
  String get queueUndoTitle;

  /// No description provided for @queueUndoBody.
  ///
  /// In en, this message translates to:
  /// **'This will return the trailer to this department\'s queue.'**
  String get queueUndoBody;

  /// No description provided for @queueReversed.
  ///
  /// In en, this message translates to:
  /// **'Step reversed successfully'**
  String get queueReversed;

  /// No description provided for @queueReverseFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to reverse: {msg}'**
  String queueReverseFailed(String msg);

  /// No description provided for @queueEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Queue Empty'**
  String get queueEmptyTitle;

  /// No description provided for @queueEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No trailers waiting in this department'**
  String get queueEmptyBody;

  /// No description provided for @queueNoStalledTitle.
  ///
  /// In en, this message translates to:
  /// **'No Stalled Trailers'**
  String get queueNoStalledTitle;

  /// No description provided for @queueNoStalledBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this department is past the stall threshold.\nTurn off the \"Stalled\" filter to see the full queue.'**
  String get queueNoStalledBody;

  /// No description provided for @queueOpenDetailTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open trailer detail'**
  String get queueOpenDetailTooltip;

  /// No description provided for @queueCompleteButton.
  ///
  /// In en, this message translates to:
  /// **'COMPLETE'**
  String get queueCompleteButton;

  /// No description provided for @queueMinutesInQueue.
  ///
  /// In en, this message translates to:
  /// **'{n}m in queue'**
  String queueMinutesInQueue(int n);

  /// No description provided for @queueHoursInQueue.
  ///
  /// In en, this message translates to:
  /// **'{n}h in queue'**
  String queueHoursInQueue(String n);

  /// No description provided for @queueDaysHoursInQueue.
  ///
  /// In en, this message translates to:
  /// **'{d}d {h}h in queue'**
  String queueDaysHoursInQueue(int d, int h);

  /// No description provided for @queueReworkBadge.
  ///
  /// In en, this message translates to:
  /// **'REWORK ×{count}'**
  String queueReworkBadge(int count);

  /// No description provided for @queueOverlayPoints.
  ///
  /// In en, this message translates to:
  /// **'+{pts} points'**
  String queueOverlayPoints(String pts);

  /// No description provided for @queueOverlayRework.
  ///
  /// In en, this message translates to:
  /// **'Completed (rework)'**
  String get queueOverlayRework;

  /// No description provided for @queueOverlayNext.
  ///
  /// In en, this message translates to:
  /// **'Next: {dept}'**
  String queueOverlayNext(String dept);

  /// No description provided for @stepCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Step'**
  String get stepCompleteTitle;

  /// No description provided for @stepChecklistRequired.
  ///
  /// In en, this message translates to:
  /// **'Answer every checklist item. Notes are required on any \"No\".'**
  String get stepChecklistRequired;

  /// No description provided for @stepChecklistLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load checklist: {msg}'**
  String stepChecklistLoadFail(String msg);

  /// No description provided for @stepHotBadge.
  ///
  /// In en, this message translates to:
  /// **'HOT'**
  String get stepHotBadge;

  /// No description provided for @stepDetailModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get stepDetailModel;

  /// No description provided for @stepDetailCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get stepDetailCustomer;

  /// No description provided for @stepDetailColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get stepDetailColor;

  /// No description provided for @stepDetailSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get stepDetailSize;

  /// No description provided for @stepDetailNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get stepDetailNotes;

  /// No description provided for @stepPdfTitle.
  ///
  /// In en, this message translates to:
  /// **'{so} — QB Sales Order'**
  String stepPdfTitle(String so);

  /// No description provided for @stepViewQbPdf.
  ///
  /// In en, this message translates to:
  /// **'View QB Sales Order'**
  String get stepViewQbPdf;

  /// No description provided for @stepFullDetails.
  ///
  /// In en, this message translates to:
  /// **'Full Details'**
  String get stepFullDetails;

  /// No description provided for @stepViewFullDetails.
  ///
  /// In en, this message translates to:
  /// **'View full trailer details'**
  String get stepViewFullDetails;

  /// No description provided for @stepReworkHeader.
  ///
  /// In en, this message translates to:
  /// **'REWORK — QC Fail Notes (×{count})'**
  String stepReworkHeader(int count);

  /// No description provided for @stepReworkWarning.
  ///
  /// In en, this message translates to:
  /// **'Rework steps award 0 points.'**
  String get stepReworkWarning;

  /// No description provided for @stepSelfCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Self-Check'**
  String get stepSelfCheckTitle;

  /// No description provided for @stepSelfCheckHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm each item before completing. Notes are required on any \"No\".'**
  String get stepSelfCheckHint;

  /// No description provided for @stepNoteRequired.
  ///
  /// In en, this message translates to:
  /// **'Note (required)'**
  String get stepNoteRequired;

  /// No description provided for @stepNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Completion Notes (optional)'**
  String get stepNotesLabel;

  /// No description provided for @stepNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Any notes about this step...'**
  String get stepNotesHint;

  /// No description provided for @stepCompleting.
  ///
  /// In en, this message translates to:
  /// **'Completing...'**
  String get stepCompleting;

  /// No description provided for @stepCompleteCta.
  ///
  /// In en, this message translates to:
  /// **'COMPLETE STEP'**
  String get stepCompleteCta;

  /// No description provided for @stepCompleteSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Step Complete!'**
  String get stepCompleteSuccessTitle;

  /// No description provided for @stepReworkSuccessPoints.
  ///
  /// In en, this message translates to:
  /// **'Rework — 0 points'**
  String get stepReworkSuccessPoints;

  /// No description provided for @stepNextDept.
  ///
  /// In en, this message translates to:
  /// **'Next → {dept}'**
  String stepNextDept(String dept);

  /// No description provided for @allQueuesTitle.
  ///
  /// In en, this message translates to:
  /// **'All Queues'**
  String get allQueuesTitle;

  /// No description provided for @allQueuesLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load queues'**
  String get allQueuesLoadFail;

  /// No description provided for @allQueuesReorderFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to reorder queue'**
  String get allQueuesReorderFail;

  /// No description provided for @allQueuesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Queue empty'**
  String get allQueuesEmpty;

  /// No description provided for @qcFilterRework.
  ///
  /// In en, this message translates to:
  /// **'Rework'**
  String get qcFilterRework;

  /// No description provided for @qcReadyToInspect.
  ///
  /// In en, this message translates to:
  /// **'{n} ready to inspect'**
  String qcReadyToInspect(int n);

  /// No description provided for @qcInspectionsPending.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 inspection pending} other{{n} inspections pending}}'**
  String qcInspectionsPending(int n);

  /// No description provided for @qcNoReworkTitle.
  ///
  /// In en, this message translates to:
  /// **'No Rework Items'**
  String get qcNoReworkTitle;

  /// No description provided for @qcNoInspectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to Inspect'**
  String get qcNoInspectionsTitle;

  /// No description provided for @qcNoReworkBody.
  ///
  /// In en, this message translates to:
  /// **'No rework inspections in the queue.'**
  String get qcNoReworkBody;

  /// No description provided for @qcAllInspectedBody.
  ///
  /// In en, this message translates to:
  /// **'All ready inspections are done.'**
  String get qcAllInspectedBody;

  /// No description provided for @qcQueuesClearBody.
  ///
  /// In en, this message translates to:
  /// **'All QC queues are clear.'**
  String get qcQueuesClearBody;

  /// No description provided for @qcSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by SO number'**
  String get qcSearchHint;

  /// No description provided for @qcSearchNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get qcSearchNoMatchTitle;

  /// No description provided for @qcSearchNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'No active inspections match \"{query}\".'**
  String qcSearchNoMatchBody(String query);

  /// No description provided for @qcInfoModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get qcInfoModel;

  /// No description provided for @qcInfoSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get qcInfoSize;

  /// No description provided for @qcInfoColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get qcInfoColor;

  /// No description provided for @qcInfoCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get qcInfoCustomer;

  /// No description provided for @qcInfoSaleStatus.
  ///
  /// In en, this message translates to:
  /// **'Sale Status'**
  String get qcInfoSaleStatus;

  /// No description provided for @qcInfoOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get qcInfoOptions;

  /// No description provided for @qcInfoSpecialNote.
  ///
  /// In en, this message translates to:
  /// **'Special Note'**
  String get qcInfoSpecialNote;

  /// No description provided for @announcementDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get announcementDefaultTitle;

  /// No description provided for @announcementPostedBy.
  ///
  /// In en, this message translates to:
  /// **'Posted by {name}'**
  String announcementPostedBy(String name);

  /// No description provided for @announcementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcementsTitle;

  /// No description provided for @announcementsNew.
  ///
  /// In en, this message translates to:
  /// **'New Announcement'**
  String get announcementsNew;

  /// No description provided for @announcementsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No announcements yet.'**
  String get announcementsEmpty;

  /// No description provided for @announcementsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get announcementsActive;

  /// No description provided for @announcementsInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get announcementsInactive;

  /// No description provided for @announcementsAckProgress.
  ///
  /// In en, this message translates to:
  /// **'{acked} of {total} acknowledged'**
  String announcementsAckProgress(int acked, int total);

  /// No description provided for @announcementsActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get announcementsActivate;

  /// No description provided for @announcementsDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get announcementsDeactivate;

  /// No description provided for @announcementsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete announcement?'**
  String get announcementsDeleteTitle;

  /// No description provided for @announcementsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the announcement and all acknowledgement history. Set Active=false instead to keep the trail.'**
  String get announcementsDeleteBody;

  /// No description provided for @announcementsTitleField.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get announcementsTitleField;

  /// No description provided for @announcementsBodyField.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get announcementsBodyField;

  /// No description provided for @announcementsBodyRequired.
  ///
  /// In en, this message translates to:
  /// **'Message is required'**
  String get announcementsBodyRequired;

  /// No description provided for @announcementsNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry — runs until deactivated'**
  String get announcementsNoExpiry;

  /// No description provided for @announcementsExpiresOn.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String announcementsExpiresOn(String date);

  /// No description provided for @announcementsSetExpiry.
  ///
  /// In en, this message translates to:
  /// **'Set expiry'**
  String get announcementsSetExpiry;

  /// No description provided for @announcementsPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish to all users'**
  String get announcementsPublish;

  /// No description provided for @qcEarlierStageFallback.
  ///
  /// In en, this message translates to:
  /// **'an earlier stage'**
  String get qcEarlierStageFallback;

  /// No description provided for @qcStillAtStage.
  ///
  /// In en, this message translates to:
  /// **'{so} is still at {stage}. Inspect when it reaches {dept}.'**
  String qcStillAtStage(String so, String stage, String dept);

  /// No description provided for @qcReadyCount.
  ///
  /// In en, this message translates to:
  /// **'{n} ready'**
  String qcReadyCount(int n);

  /// No description provided for @qcUpcomingCount.
  ///
  /// In en, this message translates to:
  /// **'· {n} upcoming'**
  String qcUpcomingCount(int n);

  /// No description provided for @qcCurrentlyAt.
  ///
  /// In en, this message translates to:
  /// **'Currently at: {name}'**
  String qcCurrentlyAt(String name);

  /// No description provided for @qcUpcomingChip.
  ///
  /// In en, this message translates to:
  /// **'UPCOMING'**
  String get qcUpcomingChip;

  /// No description provided for @qcAnswerAll.
  ///
  /// In en, this message translates to:
  /// **'Please answer all checklist items'**
  String get qcAnswerAll;

  /// No description provided for @qcFillRequired.
  ///
  /// In en, this message translates to:
  /// **'Please fill all required fields'**
  String get qcFillRequired;

  /// No description provided for @qcInspectTitle.
  ///
  /// In en, this message translates to:
  /// **'Inspect {so}'**
  String qcInspectTitle(String so);

  /// No description provided for @qcSubmittingInspection.
  ///
  /// In en, this message translates to:
  /// **'Submitting inspection...'**
  String get qcSubmittingInspection;

  /// No description provided for @qcStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Step 1: Photos'**
  String get qcStep1Title;

  /// No description provided for @qcStep1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Photos are optional'**
  String get qcStep1Subtitle;

  /// No description provided for @qcStep1PendingUploads.
  ///
  /// In en, this message translates to:
  /// **'Please wait for pending uploads to finish before continuing'**
  String get qcStep1PendingUploads;

  /// No description provided for @qcInspectionPhotos.
  ///
  /// In en, this message translates to:
  /// **'QC Inspection Photos'**
  String get qcInspectionPhotos;

  /// No description provided for @qcNextChecklist.
  ///
  /// In en, this message translates to:
  /// **'Next: Checklist'**
  String get qcNextChecklist;

  /// No description provided for @qcStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Step 2: Checklist'**
  String get qcStep2Title;

  /// No description provided for @qcChecklistNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No checklist items configured for this department'**
  String get qcChecklistNotConfigured;

  /// No description provided for @qcChecklistLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Could not load checklist'**
  String get qcChecklistLoadFail;

  /// No description provided for @qcNextResult.
  ///
  /// In en, this message translates to:
  /// **'Next: Result'**
  String get qcNextResult;

  /// No description provided for @qcAnsweredOf.
  ///
  /// In en, this message translates to:
  /// **'{n} of {total}'**
  String qcAnsweredOf(int n, int total);

  /// No description provided for @qcOptionalNote.
  ///
  /// In en, this message translates to:
  /// **'Optional note...'**
  String get qcOptionalNote;

  /// No description provided for @qcPass.
  ///
  /// In en, this message translates to:
  /// **'PASS'**
  String get qcPass;

  /// No description provided for @qcFail.
  ///
  /// In en, this message translates to:
  /// **'FAIL'**
  String get qcFail;

  /// No description provided for @qcWorker.
  ///
  /// In en, this message translates to:
  /// **'Worker'**
  String get qcWorker;

  /// No description provided for @qcUpstreamMarkedPrefix.
  ///
  /// In en, this message translates to:
  /// **'{who}{dept} marked '**
  String qcUpstreamMarkedPrefix(String who, String dept);

  /// No description provided for @qcUpstreamFailedCount.
  ///
  /// In en, this message translates to:
  /// **'Upstream self-checks: {f} failed of {t}'**
  String qcUpstreamFailedCount(int f, int t);

  /// No description provided for @qcUpstreamAllPassed.
  ///
  /// In en, this message translates to:
  /// **'All {n} upstream self-checks passed'**
  String qcUpstreamAllPassed(int n);

  /// No description provided for @qcStep3Title.
  ///
  /// In en, this message translates to:
  /// **'Step 3: Inspection Result'**
  String get qcStep3Title;

  /// No description provided for @qcStep3Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the final inspection result'**
  String get qcStep3Subtitle;

  /// No description provided for @qcFinalQcWarning.
  ///
  /// In en, this message translates to:
  /// **'FINAL QC — Passing will mark trailer as Ready for Delivery'**
  String get qcFinalQcWarning;

  /// No description provided for @qcSubmitInspection.
  ///
  /// In en, this message translates to:
  /// **'Submit Inspection'**
  String get qcSubmitInspection;

  /// No description provided for @qcNextFailDetails.
  ///
  /// In en, this message translates to:
  /// **'Next: Fail Details'**
  String get qcNextFailDetails;

  /// No description provided for @qcStep4Title.
  ///
  /// In en, this message translates to:
  /// **'Step 4: Fail Details'**
  String get qcStep4Title;

  /// No description provided for @qcStep4Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Describe the defect and select rework department'**
  String get qcStep4Subtitle;

  /// No description provided for @qcFailNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Fail Notes *'**
  String get qcFailNotesLabel;

  /// No description provided for @qcFailNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what failed and needs to be fixed...'**
  String get qcFailNotesHint;

  /// No description provided for @qcReworkTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Rework Target Department *'**
  String get qcReworkTargetLabel;

  /// No description provided for @qcSelectDept.
  ///
  /// In en, this message translates to:
  /// **'Select department...'**
  String get qcSelectDept;

  /// No description provided for @qcInsertedAtPriorityOne.
  ///
  /// In en, this message translates to:
  /// **'This trailer will be inserted at #1 priority in {dept}\'s queue'**
  String qcInsertedAtPriorityOne(String dept);

  /// No description provided for @qcTheSelectedDept.
  ///
  /// In en, this message translates to:
  /// **'the selected department'**
  String get qcTheSelectedDept;

  /// No description provided for @qcResultPassed.
  ///
  /// In en, this message translates to:
  /// **'QC PASSED'**
  String get qcResultPassed;

  /// No description provided for @qcResultFailed.
  ///
  /// In en, this message translates to:
  /// **'QC FAILED'**
  String get qcResultFailed;

  /// No description provided for @qcReadyForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Trailer Ready for Delivery!'**
  String get qcReadyForDelivery;

  /// No description provided for @qcSmsSent.
  ///
  /// In en, this message translates to:
  /// **'SMS Sent'**
  String get qcSmsSent;

  /// No description provided for @qcSendSms.
  ///
  /// In en, this message translates to:
  /// **'Send Customer SMS'**
  String get qcSendSms;

  /// No description provided for @qcCustomerSmsSent.
  ///
  /// In en, this message translates to:
  /// **'Customer SMS sent'**
  String get qcCustomerSmsSent;

  /// No description provided for @qcSmsFailed.
  ///
  /// In en, this message translates to:
  /// **'SMS failed: {msg}'**
  String qcSmsFailed(String msg);

  /// No description provided for @qcSmsFailedRetry.
  ///
  /// In en, this message translates to:
  /// **'SMS failed — please retry'**
  String get qcSmsFailedRetry;

  /// No description provided for @qcReworkSentTo.
  ///
  /// In en, this message translates to:
  /// **'Rework sent to {dept} at Priority #{pos}'**
  String qcReworkSentTo(String dept, int pos);

  /// No description provided for @qcManagersNotified.
  ///
  /// In en, this message translates to:
  /// **'Production managers have been notified'**
  String get qcManagersNotified;

  /// No description provided for @qcInspectionLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load inspection'**
  String get qcInspectionLoadFail;

  /// No description provided for @qcInspectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Inspection #{id}'**
  String qcInspectionTitle(int id);

  /// No description provided for @qcStatusPassed.
  ///
  /// In en, this message translates to:
  /// **'PASSED'**
  String get qcStatusPassed;

  /// No description provided for @qcStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'FAILED'**
  String get qcStatusFailed;

  /// No description provided for @qcAttemptNumber.
  ///
  /// In en, this message translates to:
  /// **'Attempt #{n}'**
  String qcAttemptNumber(int n);

  /// No description provided for @qcFailNotesHeader.
  ///
  /// In en, this message translates to:
  /// **'Fail Notes'**
  String get qcFailNotesHeader;

  /// No description provided for @qcPhotosCount.
  ///
  /// In en, this message translates to:
  /// **'Photos ({n})'**
  String qcPhotosCount(int n);

  /// No description provided for @qcChecklistCount.
  ///
  /// In en, this message translates to:
  /// **'Checklist ({n} items)'**
  String qcChecklistCount(int n);

  /// No description provided for @qcItemNumber.
  ///
  /// In en, this message translates to:
  /// **'Item #{id}'**
  String qcItemNumber(int id);

  /// No description provided for @qcPhotoNumber.
  ///
  /// In en, this message translates to:
  /// **'Photo {n}'**
  String qcPhotoNumber(int n);

  /// No description provided for @qcMgmtLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load checklist items'**
  String get qcMgmtLoadFail;

  /// No description provided for @qcMgmtAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Checklist Item'**
  String get qcMgmtAddTitle;

  /// No description provided for @qcMgmtDeptLabel.
  ///
  /// In en, this message translates to:
  /// **'QC Department'**
  String get qcMgmtDeptLabel;

  /// No description provided for @qcMgmtLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get qcMgmtLabelField;

  /// No description provided for @qcMgmtSortOrder.
  ///
  /// In en, this message translates to:
  /// **'Sort Order'**
  String get qcMgmtSortOrder;

  /// No description provided for @qcMgmtSeriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Applies To Series'**
  String get qcMgmtSeriesLabel;

  /// No description provided for @qcMgmtAllSeries.
  ///
  /// In en, this message translates to:
  /// **'All Series'**
  String get qcMgmtAllSeries;

  /// No description provided for @qcMgmtCreateFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create: {msg}'**
  String qcMgmtCreateFail(String msg);

  /// No description provided for @qcMgmtEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Checklist Item'**
  String get qcMgmtEditTitle;

  /// No description provided for @qcMgmtDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get qcMgmtDeactivate;

  /// No description provided for @qcMgmtScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'QC Checklist Items'**
  String get qcMgmtScreenTitle;

  /// No description provided for @qcMgmtEmpty.
  ///
  /// In en, this message translates to:
  /// **'No checklist items'**
  String get qcMgmtEmpty;

  /// No description provided for @qcMgmtSeriesValue.
  ///
  /// In en, this message translates to:
  /// **'Series: {series}'**
  String qcMgmtSeriesValue(String series);

  /// No description provided for @qcMgmtSeriesValueInactive.
  ///
  /// In en, this message translates to:
  /// **'Series: {series} (inactive)'**
  String qcMgmtSeriesValueInactive(String series);

  /// No description provided for @qcMgmtDeptFallback.
  ///
  /// In en, this message translates to:
  /// **'Dept {id}'**
  String qcMgmtDeptFallback(int id);

  /// No description provided for @payrollWeeklyReport.
  ///
  /// In en, this message translates to:
  /// **'Weekly Report'**
  String get payrollWeeklyReport;

  /// No description provided for @payrollPointMatrix.
  ///
  /// In en, this message translates to:
  /// **'Point Matrix'**
  String get payrollPointMatrix;

  /// No description provided for @payrollDollarRates.
  ///
  /// In en, this message translates to:
  /// **'Dollar Rates'**
  String get payrollDollarRates;

  /// No description provided for @payrollCurrentWeekSummary.
  ///
  /// In en, this message translates to:
  /// **'Current Week Summary'**
  String get payrollCurrentWeekSummary;

  /// No description provided for @payrollTotalPoints.
  ///
  /// In en, this message translates to:
  /// **'Total Points'**
  String get payrollTotalPoints;

  /// No description provided for @payrollProjected.
  ///
  /// In en, this message translates to:
  /// **'Projected'**
  String get payrollProjected;

  /// No description provided for @payrollSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get payrollSteps;

  /// No description provided for @payrollReworks.
  ///
  /// In en, this message translates to:
  /// **'Reworks: {n}'**
  String payrollReworks(int n);

  /// No description provided for @payrollDailyBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Daily Breakdown (Sun-Sat)'**
  String get payrollDailyBreakdown;

  /// No description provided for @payrollDaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get payrollDaySun;

  /// No description provided for @payrollDayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get payrollDayMon;

  /// No description provided for @payrollDayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get payrollDayTue;

  /// No description provided for @payrollDayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get payrollDayWed;

  /// No description provided for @payrollDayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get payrollDayThu;

  /// No description provided for @payrollDayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get payrollDayFri;

  /// No description provided for @payrollDaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get payrollDaySat;

  /// No description provided for @payrollEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated from available API data'**
  String get payrollEstimated;

  /// No description provided for @payrollDeptBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Department Breakdown'**
  String get payrollDeptBreakdown;

  /// No description provided for @payrollDeptEmpty.
  ///
  /// In en, this message translates to:
  /// **'No department activity this week'**
  String get payrollDeptEmpty;

  /// No description provided for @payrollPtsSuffix.
  ///
  /// In en, this message translates to:
  /// **'{n} pts'**
  String payrollPtsSuffix(String n);

  /// No description provided for @payrollHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get payrollHistory;

  /// No description provided for @payrollHistoryNoAccess.
  ///
  /// In en, this message translates to:
  /// **'History endpoint is manager-only in current API permissions'**
  String get payrollHistoryNoAccess;

  /// No description provided for @payrollHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No historical records found'**
  String get payrollHistoryEmpty;

  /// No description provided for @payrollDepartmentFallback.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get payrollDepartmentFallback;

  /// No description provided for @payrollWeeklyReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly Payroll Report'**
  String get payrollWeeklyReportTitle;

  /// No description provided for @payrollLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock Payroll Week'**
  String get payrollLockTitle;

  /// No description provided for @payrollLockBody.
  ///
  /// In en, this message translates to:
  /// **'Lock payroll for {date}? This cannot be undone.'**
  String payrollLockBody(String date);

  /// No description provided for @payrollLockConfirm.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get payrollLockConfirm;

  /// No description provided for @payrollWeekLocked.
  ///
  /// In en, this message translates to:
  /// **'Payroll week locked'**
  String get payrollWeekLocked;

  /// No description provided for @payrollAlreadyLocked.
  ///
  /// In en, this message translates to:
  /// **'Already locked'**
  String get payrollAlreadyLocked;

  /// No description provided for @payrollDateMustBeSunday.
  ///
  /// In en, this message translates to:
  /// **'Date must be a Sunday'**
  String get payrollDateMustBeSunday;

  /// No description provided for @payrollLockFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to lock week: {msg}'**
  String payrollLockFailed(String msg);

  /// No description provided for @payrollCsvPrepared.
  ///
  /// In en, this message translates to:
  /// **'CSV prepared ({n} chars)'**
  String payrollCsvPrepared(int n);

  /// No description provided for @payrollCsvChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Export weekly report'**
  String get payrollCsvChooseTitle;

  /// No description provided for @payrollCsvShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get payrollCsvShare;

  /// No description provided for @payrollCsvShareSub.
  ///
  /// In en, this message translates to:
  /// **'Send via apps, email, or Files'**
  String get payrollCsvShareSub;

  /// No description provided for @payrollCsvSave.
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get payrollCsvSave;

  /// No description provided for @payrollCsvSaveSub.
  ///
  /// In en, this message translates to:
  /// **'Choose where to store the .csv'**
  String get payrollCsvSaveSub;

  /// No description provided for @payrollCsvSaved.
  ///
  /// In en, this message translates to:
  /// **'CSV saved to device'**
  String get payrollCsvSaved;

  /// No description provided for @payrollCsvExportFail.
  ///
  /// In en, this message translates to:
  /// **'CSV export failed: {msg}'**
  String payrollCsvExportFail(String msg);

  /// No description provided for @payrollWeekIsLocked.
  ///
  /// In en, this message translates to:
  /// **'Week is locked'**
  String get payrollWeekIsLocked;

  /// No description provided for @payrollExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get payrollExportCsv;

  /// No description provided for @payrollLockWeek.
  ///
  /// In en, this message translates to:
  /// **'Lock Week'**
  String get payrollLockWeek;

  /// No description provided for @payrollColName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get payrollColName;

  /// No description provided for @payrollColPoints.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get payrollColPoints;

  /// No description provided for @payrollColReworks.
  ///
  /// In en, this message translates to:
  /// **'Reworks'**
  String get payrollColReworks;

  /// No description provided for @payrollColGross.
  ///
  /// In en, this message translates to:
  /// **'Gross'**
  String get payrollColGross;

  /// No description provided for @payrollTotals.
  ///
  /// In en, this message translates to:
  /// **'Totals: {points} points • \$ {gross}'**
  String payrollTotals(String points, String gross);

  /// No description provided for @payrollPmTitle.
  ///
  /// In en, this message translates to:
  /// **'Point Values Matrix'**
  String get payrollPmTitle;

  /// No description provided for @payrollPmAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add point value'**
  String get payrollPmAddTooltip;

  /// No description provided for @payrollPmNoData.
  ///
  /// In en, this message translates to:
  /// **'No production departments or trailer models are configured yet.'**
  String get payrollPmNoData;

  /// No description provided for @payrollPmTapCell.
  ///
  /// In en, this message translates to:
  /// **'Tap any cell to set or edit its points.'**
  String get payrollPmTapCell;

  /// No description provided for @payrollPmDept.
  ///
  /// In en, this message translates to:
  /// **'Department'**
  String get payrollPmDept;

  /// No description provided for @payrollPmLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Could not load the point matrix.\n{msg}'**
  String payrollPmLoadFail(String msg);

  /// No description provided for @payrollPmNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Departments and trailer models not loaded yet.'**
  String get payrollPmNotLoaded;

  /// No description provided for @payrollPmAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Point Value'**
  String get payrollPmAddTitle;

  /// No description provided for @payrollPmTrailerModel.
  ///
  /// In en, this message translates to:
  /// **'Trailer Model'**
  String get payrollPmTrailerModel;

  /// No description provided for @payrollPmSelectDept.
  ///
  /// In en, this message translates to:
  /// **'Select a department'**
  String get payrollPmSelectDept;

  /// No description provided for @payrollPmSelectModel.
  ///
  /// In en, this message translates to:
  /// **'Select a trailer model'**
  String get payrollPmSelectModel;

  /// No description provided for @payrollPmPointsLabel.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get payrollPmPointsLabel;

  /// No description provided for @payrollPmEffective.
  ///
  /// In en, this message translates to:
  /// **'Effective: {date}'**
  String payrollPmEffective(String date);

  /// No description provided for @payrollPmAddFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to add point value: {msg}'**
  String payrollPmAddFail(String msg);

  /// No description provided for @payrollPmSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set Point Value'**
  String get payrollPmSetTitle;

  /// No description provided for @payrollPmEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Point Value'**
  String get payrollPmEditTitle;

  /// No description provided for @payrollPmSaveFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to save: {msg}'**
  String payrollPmSaveFail(String msg);

  /// No description provided for @payrollDrTitle.
  ///
  /// In en, this message translates to:
  /// **'Dollar Rates'**
  String get payrollDrTitle;

  /// No description provided for @payrollDrEmpty.
  ///
  /// In en, this message translates to:
  /// **'No dollar rates yet. Tap + to add one.'**
  String get payrollDrEmpty;

  /// No description provided for @payrollDrDeptFallback.
  ///
  /// In en, this message translates to:
  /// **'Department {id}'**
  String payrollDrDeptFallback(int id);

  /// No description provided for @payrollDrCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current: \$ {rate} / point'**
  String payrollDrCurrent(String rate);

  /// No description provided for @payrollDrRatePerPoint.
  ///
  /// In en, this message translates to:
  /// **'\$ {rate} / point'**
  String payrollDrRatePerPoint(String rate);

  /// No description provided for @payrollDrFromTo.
  ///
  /// In en, this message translates to:
  /// **'From {start} to {end}'**
  String payrollDrFromTo(String start, String end);

  /// No description provided for @payrollDrPresent.
  ///
  /// In en, this message translates to:
  /// **'present'**
  String get payrollDrPresent;

  /// No description provided for @payrollDrDeptsNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Departments not loaded yet. Try again.'**
  String get payrollDrDeptsNotLoaded;

  /// No description provided for @payrollDrAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Dollar Rate'**
  String get payrollDrAddTitle;

  /// No description provided for @payrollDrDollarLabel.
  ///
  /// In en, this message translates to:
  /// **'Dollar per Point'**
  String get payrollDrDollarLabel;

  /// No description provided for @payrollDrValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid positive number'**
  String get payrollDrValidNumber;

  /// No description provided for @payrollDrAddFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to add rate: {msg}'**
  String payrollDrAddFail(String msg);

  /// No description provided for @payrollDrDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete dollar rate?'**
  String get payrollDrDeleteTitle;

  /// No description provided for @payrollDrDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Remove the \${rate}/point rate for {dept}? This cannot be undone.'**
  String payrollDrDeleteBody(String rate, String dept);

  /// No description provided for @payrollDrDeleteFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete rate: {msg}'**
  String payrollDrDeleteFail(String msg);

  /// No description provided for @customersTitle.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customersTitle;

  /// No description provided for @customersLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Unable to load customers: {msg}'**
  String customersLoadFail(String msg);

  /// No description provided for @customersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name or company'**
  String get customersSearchHint;

  /// No description provided for @customersFilterType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get customersFilterType;

  /// No description provided for @customersFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get customersFilterAll;

  /// No description provided for @customerTypeEndUser.
  ///
  /// In en, this message translates to:
  /// **'End User'**
  String get customerTypeEndUser;

  /// No description provided for @customerTypeDealer.
  ///
  /// In en, this message translates to:
  /// **'Dealer'**
  String get customerTypeDealer;

  /// No description provided for @customerTypeStockLoc.
  ///
  /// In en, this message translates to:
  /// **'Stock Loc'**
  String get customerTypeStockLoc;

  /// No description provided for @customerTypeStockLocation.
  ///
  /// In en, this message translates to:
  /// **'Stock Location'**
  String get customerTypeStockLocation;

  /// No description provided for @customerTypeStockShort.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get customerTypeStockShort;

  /// No description provided for @customersActiveTrailers.
  ///
  /// In en, this message translates to:
  /// **'Active trailers: {n}'**
  String customersActiveTrailers(int n);

  /// No description provided for @customersPrev.
  ///
  /// In en, this message translates to:
  /// **'Prev'**
  String get customersPrev;

  /// No description provided for @customersNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get customersNext;

  /// No description provided for @customersPageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {n} / {total}'**
  String customersPageOf(int n, int total);

  /// No description provided for @customersNew.
  ///
  /// In en, this message translates to:
  /// **'New Customer'**
  String get customersNew;

  /// No description provided for @customerFormCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Customer'**
  String get customerFormCreateTitle;

  /// No description provided for @customerFormEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Customer'**
  String get customerFormEditTitle;

  /// No description provided for @customerFormName.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get customerFormName;

  /// No description provided for @customerFormCompany.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get customerFormCompany;

  /// No description provided for @customerFormType.
  ///
  /// In en, this message translates to:
  /// **'Customer Type'**
  String get customerFormType;

  /// No description provided for @customerFormPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get customerFormPhone;

  /// No description provided for @customerFormEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get customerFormEmail;

  /// No description provided for @customerFormBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing Address'**
  String get customerFormBilling;

  /// No description provided for @customerFormDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery Address'**
  String get customerFormDelivery;

  /// No description provided for @customerFormSmsOptOut.
  ///
  /// In en, this message translates to:
  /// **'SMS Opt-out'**
  String get customerFormSmsOptOut;

  /// No description provided for @customerFormNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get customerFormNotes;

  /// No description provided for @customerFormSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get customerFormSaveChanges;

  /// No description provided for @customerFormSaveFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to save customer: {msg}'**
  String customerFormSaveFail(String msg);

  /// No description provided for @customerDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Detail'**
  String get customerDetailTitle;

  /// No description provided for @customerDetailLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Unable to load customer detail: {msg}'**
  String customerDetailLoadFail(String msg);

  /// No description provided for @customerDetailDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete customer'**
  String get customerDetailDeleteTooltip;

  /// No description provided for @customerDetailTabTrailers.
  ///
  /// In en, this message translates to:
  /// **'Trailer History'**
  String get customerDetailTabTrailers;

  /// No description provided for @customerDetailTabDeliveries.
  ///
  /// In en, this message translates to:
  /// **'Delivery History'**
  String get customerDetailTabDeliveries;

  /// No description provided for @customerDetailNotFound.
  ///
  /// In en, this message translates to:
  /// **'Customer not found'**
  String get customerDetailNotFound;

  /// No description provided for @customerDetailDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete customer?'**
  String get customerDetailDeleteTitle;

  /// No description provided for @customerDetailDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes \"{name}\".'**
  String customerDetailDeleteBody(String name);

  /// No description provided for @customerDetailHasTrailersTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer has trailers'**
  String get customerDetailHasTrailersTitle;

  /// No description provided for @customerDetailHasTrailersBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is referenced by {n, plural, =1{1 trailer} other{{n} trailers}}.\n\nDeleting the customer will also delete every associated trailer along with its production history, QC inspections, photos, deliveries, and messages.\n\nThis cannot be undone.'**
  String customerDetailHasTrailersBody(String name, int n);

  /// No description provided for @customerDetailDeleteCascade.
  ///
  /// In en, this message translates to:
  /// **'Delete customer + {n, plural, =1{1 trailer} other{{n} trailers}}'**
  String customerDetailDeleteCascade(int n);

  /// No description provided for @customerDetailDeletedCascade.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\" and {n, plural, =1{1 trailer} other{{n} trailers}}'**
  String customerDetailDeletedCascade(String name, int n);

  /// No description provided for @customerDetailDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted customer \"{name}\"'**
  String customerDetailDeleted(String name);

  /// No description provided for @customerDetailDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {msg}'**
  String customerDetailDeleteFailed(String msg);

  /// No description provided for @customerDetailSmsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update SMS preference: {msg}'**
  String customerDetailSmsUpdateFailed(String msg);

  /// No description provided for @customerDetailPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone: {value}'**
  String customerDetailPhone(String value);

  /// No description provided for @customerDetailEmail.
  ///
  /// In en, this message translates to:
  /// **'Email: {value}'**
  String customerDetailEmail(String value);

  /// No description provided for @customerDetailQbId.
  ///
  /// In en, this message translates to:
  /// **'QuickBooks ID: {value}'**
  String customerDetailQbId(String value);

  /// No description provided for @customerDetailUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating...'**
  String get customerDetailUpdating;

  /// No description provided for @customerDetailBilling.
  ///
  /// In en, this message translates to:
  /// **'Billing Address: {value}'**
  String customerDetailBilling(String value);

  /// No description provided for @customerDetailDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery Address: {value}'**
  String customerDetailDelivery(String value);

  /// No description provided for @customerDetailNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes: {value}'**
  String customerDetailNotes(String value);

  /// No description provided for @customerDetailNoTrailerHistory.
  ///
  /// In en, this message translates to:
  /// **'No trailer history'**
  String get customerDetailNoTrailerHistory;

  /// No description provided for @customerDetailNoDeliveryHistory.
  ///
  /// In en, this message translates to:
  /// **'No delivery history'**
  String get customerDetailNoDeliveryHistory;

  /// No description provided for @customerDetailVin.
  ///
  /// In en, this message translates to:
  /// **'VIN: {value}'**
  String customerDetailVin(String value);

  /// No description provided for @customerDetailStatusValue.
  ///
  /// In en, this message translates to:
  /// **'Status: {value}'**
  String customerDetailStatusValue(String value);

  /// No description provided for @customerDetailOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get customerDetailOpen;

  /// No description provided for @customerDetailDeliveryHash.
  ///
  /// In en, this message translates to:
  /// **'Delivery #{id}'**
  String customerDetailDeliveryHash(int id);

  /// No description provided for @customerDetailTrailerValue.
  ///
  /// In en, this message translates to:
  /// **'Trailer: {value}'**
  String customerDetailTrailerValue(String value);

  /// No description provided for @customerDetailTypeStatus.
  ///
  /// In en, this message translates to:
  /// **'Type: {type} • Status: {status}'**
  String customerDetailTypeStatus(String type, String status);

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Center'**
  String get notificationsTitle;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notificationsEmpty;

  /// No description provided for @notificationsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get notificationsDelete;

  /// No description provided for @messagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Trailer #{id} Messages'**
  String messagesTitle(int id);

  /// No description provided for @messagesRecipientLabel.
  ///
  /// In en, this message translates to:
  /// **'Recipient User ID'**
  String get messagesRecipientLabel;

  /// No description provided for @messagesUserFallback.
  ///
  /// In en, this message translates to:
  /// **'User {id}'**
  String messagesUserFallback(int id);

  /// No description provided for @messagesHint.
  ///
  /// In en, this message translates to:
  /// **'Message...'**
  String get messagesHint;

  /// No description provided for @messagesSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get messagesSend;

  /// No description provided for @messagesSendFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to send message: {msg}'**
  String messagesSendFail(String msg);

  /// No description provided for @notificationPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationPanelTitle;

  /// No description provided for @deliveryListTabScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get deliveryListTabScheduled;

  /// No description provided for @deliveryListTabCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get deliveryListTabCompleted;

  /// No description provided for @deliveryListTabFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get deliveryListTabFailed;

  /// No description provided for @deliveryListFabBatches.
  ///
  /// In en, this message translates to:
  /// **'Batches'**
  String get deliveryListFabBatches;

  /// No description provided for @deliveryListFabCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Delivery'**
  String get deliveryListFabCreate;

  /// No description provided for @deliveryListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No deliveries found'**
  String get deliveryListEmpty;

  /// No description provided for @deliveryListSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by SO# or customer...'**
  String get deliveryListSearchHint;

  /// No description provided for @deliveryListSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No deliveries match your search'**
  String get deliveryListSearchEmpty;

  /// No description provided for @deliveryListFilterType.
  ///
  /// In en, this message translates to:
  /// **'Delivery Type'**
  String get deliveryListFilterType;

  /// No description provided for @deliveryListFilterAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get deliveryListFilterAllTypes;

  /// No description provided for @deliveryListFilterFactoryPickup.
  ///
  /// In en, this message translates to:
  /// **'Factory Pickup'**
  String get deliveryListFilterFactoryPickup;

  /// No description provided for @deliveryListFilterSinglePull.
  ///
  /// In en, this message translates to:
  /// **'Single Pull'**
  String get deliveryListFilterSinglePull;

  /// No description provided for @deliveryListFilterStackToDealer.
  ///
  /// In en, this message translates to:
  /// **'Stack to Dealer'**
  String get deliveryListFilterStackToDealer;

  /// No description provided for @deliveryListFilterStackToLocation.
  ///
  /// In en, this message translates to:
  /// **'Stack to Location'**
  String get deliveryListFilterStackToLocation;

  /// No description provided for @deliveryListFilterDriverId.
  ///
  /// In en, this message translates to:
  /// **'Driver ID'**
  String get deliveryListFilterDriverId;

  /// No description provided for @deliveryListFilterDateRange.
  ///
  /// In en, this message translates to:
  /// **'Date Range'**
  String get deliveryListFilterDateRange;

  /// No description provided for @deliveryListFilterClearDates.
  ///
  /// In en, this message translates to:
  /// **'Clear Dates'**
  String get deliveryListFilterClearDates;

  /// No description provided for @deliveryListBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch delivery — {n} trailers'**
  String deliveryListBatchTitle(int n);

  /// No description provided for @deliveryListDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination: {value}'**
  String deliveryListDestination(String value);

  /// No description provided for @deliveryListDriverLabel.
  ///
  /// In en, this message translates to:
  /// **'Driver: {value}'**
  String deliveryListDriverLabel(String value);

  /// No description provided for @deliveryListScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled: {value}'**
  String deliveryListScheduled(String value);

  /// No description provided for @deliveryDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery #{id}'**
  String deliveryDetailTitle(int id);

  /// No description provided for @deliveryDetailNotFound.
  ///
  /// In en, this message translates to:
  /// **'Delivery not found'**
  String get deliveryDetailNotFound;

  /// No description provided for @deliveryDetailDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete delivery'**
  String get deliveryDetailDeleteTooltip;

  /// No description provided for @deliveryDetailSectionTrailer.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get deliveryDetailSectionTrailer;

  /// No description provided for @deliveryDetailSectionDriver.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get deliveryDetailSectionDriver;

  /// No description provided for @deliveryDetailSectionDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get deliveryDetailSectionDestination;

  /// No description provided for @deliveryDetailSectionBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance Due'**
  String get deliveryDetailSectionBalance;

  /// No description provided for @deliveryDetailSectionPickedUp.
  ///
  /// In en, this message translates to:
  /// **'Picked Up By'**
  String get deliveryDetailSectionPickedUp;

  /// No description provided for @deliveryDetailSectionFailReason.
  ///
  /// In en, this message translates to:
  /// **'Failure Reason'**
  String get deliveryDetailSectionFailReason;

  /// No description provided for @deliveryDetailSo.
  ///
  /// In en, this message translates to:
  /// **'SO: {value}'**
  String deliveryDetailSo(String value);

  /// No description provided for @deliveryDetailModel.
  ///
  /// In en, this message translates to:
  /// **'Model: {value}'**
  String deliveryDetailModel(String value);

  /// No description provided for @deliveryDetailCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer: {value}'**
  String deliveryDetailCustomer(String value);

  /// No description provided for @deliveryDetailAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned: {value}'**
  String deliveryDetailAssigned(String value);

  /// No description provided for @deliveryDetailOpenMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get deliveryDetailOpenMaps;

  /// No description provided for @deliveryDetailTextCustomer.
  ///
  /// In en, this message translates to:
  /// **'Text Customer'**
  String get deliveryDetailTextCustomer;

  /// No description provided for @deliveryDetailCompleteAction.
  ///
  /// In en, this message translates to:
  /// **'Complete Delivery'**
  String get deliveryDetailCompleteAction;

  /// No description provided for @deliveryDetailMarkFailed.
  ///
  /// In en, this message translates to:
  /// **'Mark Failed'**
  String get deliveryDetailMarkFailed;

  /// No description provided for @deliveryDetailNoAddress.
  ///
  /// In en, this message translates to:
  /// **'No destination address for this delivery.'**
  String get deliveryDetailNoAddress;

  /// No description provided for @deliveryDetailNoPhone.
  ///
  /// In en, this message translates to:
  /// **'No phone number on file for this customer.'**
  String get deliveryDetailNoPhone;

  /// No description provided for @deliveryDetailCompleteFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to complete delivery: {msg}'**
  String deliveryDetailCompleteFail(String msg);

  /// No description provided for @deliveryDetailCompleteBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Batch'**
  String get deliveryDetailCompleteBatchTitle;

  /// No description provided for @deliveryDetailCompleteBatchBody.
  ///
  /// In en, this message translates to:
  /// **'Mark all {n} trailer(s) in {batch} as delivered? This completes the whole batch in one step.'**
  String deliveryDetailCompleteBatchBody(int n, String batch);

  /// No description provided for @deliveryDetailMarkAllDelivered.
  ///
  /// In en, this message translates to:
  /// **'Mark All Delivered'**
  String get deliveryDetailMarkAllDelivered;

  /// No description provided for @deliveryDetailBatchAllDelivered.
  ///
  /// In en, this message translates to:
  /// **'{batch} — all trailers delivered.'**
  String deliveryDetailBatchAllDelivered(String batch);

  /// No description provided for @deliveryDetailBatchFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to complete batch: {msg}'**
  String deliveryDetailBatchFail(String msg);

  /// No description provided for @deliveryDetailDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Delivery'**
  String get deliveryDetailDeleteTitle;

  /// No description provided for @deliveryDetailDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this delivery for {so}? The trailer goes back to ready for delivery. This cannot be undone.'**
  String deliveryDetailDeleteBody(String so);

  /// No description provided for @deliveryDetailDeleted.
  ///
  /// In en, this message translates to:
  /// **'{so} delivery deleted.'**
  String deliveryDetailDeleted(String so);

  /// No description provided for @deliveryDetailDeleteFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete delivery: {msg}'**
  String deliveryDetailDeleteFail(String msg);

  /// No description provided for @deliveryDetailMarkFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark Delivery Failed'**
  String get deliveryDetailMarkFailedTitle;

  /// No description provided for @deliveryDetailMarkFailedError.
  ///
  /// In en, this message translates to:
  /// **'Failed to mark failed: {msg}'**
  String deliveryDetailMarkFailedError(String msg);

  /// No description provided for @deliveryDetailStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get deliveryDetailStatusLabel;

  /// No description provided for @deliveryDetailTrailerCount.
  ///
  /// In en, this message translates to:
  /// **'{n} trailers'**
  String deliveryDetailTrailerCount(int n);

  /// No description provided for @deliveryDetailBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch — {batch}'**
  String deliveryDetailBatchTitle(String batch);

  /// No description provided for @deliveryDetailBatchStatus.
  ///
  /// In en, this message translates to:
  /// **'Status: {value}'**
  String deliveryDetailBatchStatus(String value);

  /// No description provided for @deliveryDetailUnassigned.
  ///
  /// In en, this message translates to:
  /// **'Unassigned'**
  String get deliveryDetailUnassigned;

  /// No description provided for @deliveryDetailCompleteEntireBatch.
  ///
  /// In en, this message translates to:
  /// **'Complete Entire Batch'**
  String get deliveryDetailCompleteEntireBatch;

  /// No description provided for @driverDeliveriesTitle.
  ///
  /// In en, this message translates to:
  /// **'My Deliveries'**
  String get driverDeliveriesTitle;

  /// No description provided for @driverDeliveriesLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load deliveries: {msg}'**
  String driverDeliveriesLoadFail(String msg);

  /// No description provided for @driverCompleteBatchBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm all {n} trailer(s) in {batch} were delivered to {dest}.'**
  String driverCompleteBatchBody(int n, String batch, String dest);

  /// No description provided for @driverCompleteTrailerTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Trailer'**
  String get driverCompleteTrailerTitle;

  /// No description provided for @driverCompleteTrailerBody.
  ///
  /// In en, this message translates to:
  /// **'Mark {so} as delivered? Other trailers in the batch stay in transit.'**
  String driverCompleteTrailerBody(String so);

  /// No description provided for @driverMarkDelivered.
  ///
  /// In en, this message translates to:
  /// **'Mark Delivered'**
  String get driverMarkDelivered;

  /// No description provided for @driverTrailerDelivered.
  ///
  /// In en, this message translates to:
  /// **'{so} delivered.'**
  String driverTrailerDelivered(String so);

  /// No description provided for @driverMarkSoFailed.
  ///
  /// In en, this message translates to:
  /// **'Mark {so} Failed'**
  String driverMarkSoFailed(String so);

  /// No description provided for @driverSoMarkedFailed.
  ///
  /// In en, this message translates to:
  /// **'{so} marked failed.'**
  String driverSoMarkedFailed(String so);

  /// No description provided for @driverTheDestination.
  ///
  /// In en, this message translates to:
  /// **'the destination'**
  String get driverTheDestination;

  /// No description provided for @driverCompletedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed Today'**
  String get driverCompletedToday;

  /// No description provided for @createDeliveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Delivery'**
  String get createDeliveryTitle;

  /// No description provided for @createDeliverySubmit.
  ///
  /// In en, this message translates to:
  /// **'Create Delivery'**
  String get createDeliverySubmit;

  /// No description provided for @createDeliveryCreated.
  ///
  /// In en, this message translates to:
  /// **'Delivery created'**
  String get createDeliveryCreated;

  /// No description provided for @createDeliveryFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create delivery: {msg}'**
  String createDeliveryFail(String msg);

  /// No description provided for @batchScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery Batches'**
  String get batchScreenTitle;

  /// No description provided for @batchScreenEmpty.
  ///
  /// In en, this message translates to:
  /// **'No batches yet. Tap + to create one.'**
  String get batchScreenEmpty;

  /// No description provided for @batchScreenNewBatch.
  ///
  /// In en, this message translates to:
  /// **'New Batch'**
  String get batchScreenNewBatch;

  /// No description provided for @batchCreateFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create batch: {msg}'**
  String batchCreateFail(String msg);

  /// No description provided for @stockInventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock Inventory'**
  String get stockInventoryTitle;

  /// No description provided for @stockInventoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stock trailers found.'**
  String get stockInventoryEmpty;

  /// No description provided for @stockInventoryLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load stock inventory: {msg}'**
  String stockInventoryLoadFail(String msg);

  /// No description provided for @completeDeliveryDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Delivery'**
  String get completeDeliveryDialogTitle;

  /// No description provided for @completeDeliveryPaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Collected'**
  String get completeDeliveryPaymentLabel;

  /// No description provided for @completeDeliveryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get completeDeliveryConfirm;

  /// No description provided for @failReasonDialogLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get failReasonDialogLabel;

  /// No description provided for @failReasonDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Why did this delivery fail?'**
  String get failReasonDialogHint;

  /// No description provided for @failReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'A reason is required'**
  String get failReasonRequired;

  /// No description provided for @adminDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminDashboardTitle;

  /// No description provided for @adminStatTotalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total Users'**
  String get adminStatTotalUsers;

  /// No description provided for @adminStatActiveTrailers.
  ///
  /// In en, this message translates to:
  /// **'Active Trailers'**
  String get adminStatActiveTrailers;

  /// No description provided for @adminStatWeeklyOutput.
  ///
  /// In en, this message translates to:
  /// **'Weekly Output'**
  String get adminStatWeeklyOutput;

  /// No description provided for @adminStatQcFailRate.
  ///
  /// In en, this message translates to:
  /// **'QC Fail Rate'**
  String get adminStatQcFailRate;

  /// No description provided for @adminNavUsersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create/edit/deactivate users and filter by role'**
  String get adminNavUsersSubtitle;

  /// No description provided for @adminNavDeptsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit stall thresholds and inspect workflow mapping'**
  String get adminNavDeptsSubtitle;

  /// No description provided for @adminNavWorkflowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View 4 trailer series template steps'**
  String get adminNavWorkflowSubtitle;

  /// No description provided for @adminNavAuditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Paginated events with before/after changes'**
  String get adminNavAuditSubtitle;

  /// No description provided for @adminNavReportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly summary and worker output overview'**
  String get adminNavReportsSubtitle;

  /// No description provided for @adminNavAnnouncementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Push a message every user must acknowledge'**
  String get adminNavAnnouncementsSubtitle;

  /// No description provided for @adminNavReports.
  ///
  /// In en, this message translates to:
  /// **'Production Reports'**
  String get adminNavReports;

  /// No description provided for @adminNavWorkflowTemplates.
  ///
  /// In en, this message translates to:
  /// **'Workflow Templates'**
  String get adminNavWorkflowTemplates;

  /// No description provided for @adminUsers.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get adminUsers;

  /// No description provided for @adminAuditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get adminAuditLog;

  /// No description provided for @adminReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get adminReports;

  /// No description provided for @adminDepartmentConfig.
  ///
  /// In en, this message translates to:
  /// **'Department Config'**
  String get adminDepartmentConfig;

  /// No description provided for @adminWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Workflow Viewer'**
  String get adminWorkflow;

  /// No description provided for @adminChecklists.
  ///
  /// In en, this message translates to:
  /// **'QC Checklists'**
  String get adminChecklists;

  /// No description provided for @auditLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get auditLogTitle;

  /// No description provided for @auditLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audit entries'**
  String get auditLogEmpty;

  /// No description provided for @auditLogLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load audit log: {msg}'**
  String auditLogLoadFail(String msg);

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @reportsLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load reports: {msg}'**
  String reportsLoadFail(String msg);

  /// No description provided for @userMgmtTitle.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userMgmtTitle;

  /// No description provided for @userMgmtAdd.
  ///
  /// In en, this message translates to:
  /// **'Add User'**
  String get userMgmtAdd;

  /// No description provided for @userMgmtEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit User'**
  String get userMgmtEdit;

  /// No description provided for @userMgmtDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get userMgmtDeactivate;

  /// No description provided for @userMgmtReactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get userMgmtReactivate;

  /// No description provided for @userMgmtEmpty.
  ///
  /// In en, this message translates to:
  /// **'No users yet'**
  String get userMgmtEmpty;

  /// No description provided for @userMgmtLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load users: {msg}'**
  String userMgmtLoadFail(String msg);

  /// No description provided for @userMgmtSaveFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to save user: {msg}'**
  String userMgmtSaveFail(String msg);

  /// No description provided for @deptConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Department Config'**
  String get deptConfigTitle;

  /// No description provided for @deptConfigEmpty.
  ///
  /// In en, this message translates to:
  /// **'No departments configured'**
  String get deptConfigEmpty;

  /// No description provided for @deptConfigLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load departments: {msg}'**
  String deptConfigLoadFail(String msg);

  /// No description provided for @workflowViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Workflow Viewer'**
  String get workflowViewerTitle;

  /// No description provided for @photoCaptureTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get photoCaptureTakePhoto;

  /// No description provided for @photoCaptureFromGallery.
  ///
  /// In en, this message translates to:
  /// **'From gallery'**
  String get photoCaptureFromGallery;

  /// No description provided for @photoCaptureRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get photoCaptureRemove;

  /// No description provided for @photoCaptureUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get photoCaptureUploading;

  /// No description provided for @photoCaptureFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get photoCaptureFailed;

  /// No description provided for @imageViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get imageViewerTitle;

  /// No description provided for @pdfViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get pdfViewerTitle;

  /// No description provided for @pdfViewerLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load PDF'**
  String get pdfViewerLoadFail;

  /// No description provided for @stockLocationChipsLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock Destination'**
  String get stockLocationChipsLabel;

  /// No description provided for @stockLocationChipsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading locations...'**
  String get stockLocationChipsLoading;

  /// No description provided for @stockLocationChipsLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load locations'**
  String get stockLocationChipsLoadFail;

  /// No description provided for @adminAuditEntityType.
  ///
  /// In en, this message translates to:
  /// **'Entity Type'**
  String get adminAuditEntityType;

  /// No description provided for @adminAuditEntityTrailer.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get adminAuditEntityTrailer;

  /// No description provided for @adminAuditEntityStep.
  ///
  /// In en, this message translates to:
  /// **'Production Step'**
  String get adminAuditEntityStep;

  /// No description provided for @adminAuditEntityQcInspection.
  ///
  /// In en, this message translates to:
  /// **'QC Inspection'**
  String get adminAuditEntityQcInspection;

  /// No description provided for @adminAuditEntityDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get adminAuditEntityDelivery;

  /// No description provided for @adminAuditEntityPayroll.
  ///
  /// In en, this message translates to:
  /// **'Payroll'**
  String get adminAuditEntityPayroll;

  /// No description provided for @adminAuditEntityUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get adminAuditEntityUser;

  /// No description provided for @adminAuditUserIdLabel.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get adminAuditUserIdLabel;

  /// No description provided for @adminAuditEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No audit log entries match these filters.'**
  String get adminAuditEmptyMessage;

  /// No description provided for @adminPullToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Pull down to refresh.'**
  String get adminPullToRefresh;

  /// No description provided for @adminAuditOldValues.
  ///
  /// In en, this message translates to:
  /// **'Old Values'**
  String get adminAuditOldValues;

  /// No description provided for @adminAuditNewValues.
  ///
  /// In en, this message translates to:
  /// **'New Values'**
  String get adminAuditNewValues;

  /// No description provided for @adminReportsNoReport.
  ///
  /// In en, this message translates to:
  /// **'No report'**
  String get adminReportsNoReport;

  /// No description provided for @adminReportWeeklySteps.
  ///
  /// In en, this message translates to:
  /// **'Weekly Steps Completed'**
  String get adminReportWeeklySteps;

  /// No description provided for @adminReportWeeklyPoints.
  ///
  /// In en, this message translates to:
  /// **'Weekly Points'**
  String get adminReportWeeklyPoints;

  /// No description provided for @adminReportQcFailTrend.
  ///
  /// In en, this message translates to:
  /// **'QC Fail Trend'**
  String get adminReportQcFailTrend;

  /// No description provided for @adminReportAvgTimePerStep.
  ///
  /// In en, this message translates to:
  /// **'Avg Time Per Step'**
  String get adminReportAvgTimePerStep;

  /// No description provided for @adminReportStalledTrailers.
  ///
  /// In en, this message translates to:
  /// **'Stalled Trailers'**
  String get adminReportStalledTrailers;

  /// No description provided for @adminReportNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'N/A (endpoint not available)'**
  String get adminReportNotAvailable;

  /// No description provided for @adminReportUseProdDashboard.
  ///
  /// In en, this message translates to:
  /// **'Use production dashboard queue view'**
  String get adminReportUseProdDashboard;

  /// No description provided for @adminReportWorkerSummary.
  ///
  /// In en, this message translates to:
  /// **'Worker Summary'**
  String get adminReportWorkerSummary;

  /// No description provided for @adminReportRoleValue.
  ///
  /// In en, this message translates to:
  /// **'Role: {role}'**
  String adminReportRoleValue(String role);

  /// No description provided for @adminReportStepsPtsLine.
  ///
  /// In en, this message translates to:
  /// **'{steps} steps\n{pts} pts'**
  String adminReportStepsPtsLine(String steps, String pts);

  /// No description provided for @userMgmtSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name or email'**
  String get userMgmtSearchHint;

  /// No description provided for @userMgmtFilterRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get userMgmtFilterRole;

  /// No description provided for @userMgmtFilterStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get userMgmtFilterStatus;

  /// No description provided for @userMgmtInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get userMgmtInactive;

  /// No description provided for @userMgmtEmptyFiltered.
  ///
  /// In en, this message translates to:
  /// **'No registered users found for the current filters.'**
  String get userMgmtEmptyFiltered;

  /// No description provided for @userMgmtIdChip.
  ///
  /// In en, this message translates to:
  /// **'ID: {id}'**
  String userMgmtIdChip(int id);

  /// No description provided for @userMgmtDeptChip.
  ///
  /// In en, this message translates to:
  /// **'Dept: {value}'**
  String userMgmtDeptChip(String value);

  /// No description provided for @userMgmtLocationChip.
  ///
  /// In en, this message translates to:
  /// **'Location: {value}'**
  String userMgmtLocationChip(String value);

  /// No description provided for @userMgmtCreatedChip.
  ///
  /// In en, this message translates to:
  /// **'Created: {value}'**
  String userMgmtCreatedChip(String value);

  /// No description provided for @userMgmtNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get userMgmtNotAvailable;

  /// No description provided for @userMgmtDeactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate user?'**
  String get userMgmtDeactivateTitle;

  /// No description provided for @userMgmtDeactivateBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will lose access immediately but their history is preserved. You can reactivate later.'**
  String userMgmtDeactivateBody(String name);

  /// No description provided for @userMgmtDeactivated.
  ///
  /// In en, this message translates to:
  /// **'{name} deactivated'**
  String userMgmtDeactivated(String name);

  /// No description provided for @userMgmtReactivated.
  ///
  /// In en, this message translates to:
  /// **'{name} reactivated'**
  String userMgmtReactivated(String name);

  /// No description provided for @userMgmtDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete user?'**
  String get userMgmtDeleteTitle;

  /// No description provided for @userMgmtDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes {name} from the database. This cannot be undone.'**
  String userMgmtDeleteBody(String name);

  /// No description provided for @userMgmtDeleteHelper.
  ///
  /// In en, this message translates to:
  /// **'The user must be deactivated first. Users with historical activity (completed steps, inspections, deliveries, messages) cannot be deleted — keep them deactivated to preserve the audit trail.'**
  String get userMgmtDeleteHelper;

  /// No description provided for @userMgmtDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get userMgmtDeleteForever;

  /// No description provided for @userMgmtDeleted.
  ///
  /// In en, this message translates to:
  /// **'{name} deleted'**
  String userMgmtDeleted(String name);

  /// No description provided for @userMgmtDeleteFail.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {msg}'**
  String userMgmtDeleteFail(String msg);

  /// No description provided for @userMgmtCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get userMgmtCreateAction;

  /// No description provided for @userMgmtNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get userMgmtNameLabel;

  /// No description provided for @userMgmtPasswordOptional.
  ///
  /// In en, this message translates to:
  /// **'Password (optional)'**
  String get userMgmtPasswordOptional;

  /// No description provided for @userMgmtPhoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get userMgmtPhoneOptional;

  /// No description provided for @userMgmtDeptIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Primary Department'**
  String get userMgmtDeptIdLabel;

  /// No description provided for @userMgmtLocationIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Primary Location'**
  String get userMgmtLocationIdLabel;

  /// No description provided for @userMgmtDeptNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get userMgmtDeptNone;

  /// No description provided for @userMgmtLocationNone.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get userMgmtLocationNone;

  /// No description provided for @roleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get roleOwner;

  /// No description provided for @roleProductionManager.
  ///
  /// In en, this message translates to:
  /// **'Production Manager'**
  String get roleProductionManager;

  /// No description provided for @roleProductionManagerShort.
  ///
  /// In en, this message translates to:
  /// **'Prod Mgr'**
  String get roleProductionManagerShort;

  /// No description provided for @roleTransportManager.
  ///
  /// In en, this message translates to:
  /// **'Transport Manager'**
  String get roleTransportManager;

  /// No description provided for @roleTransportManagerShort.
  ///
  /// In en, this message translates to:
  /// **'Transport Mgr'**
  String get roleTransportManagerShort;

  /// No description provided for @roleQcInspector.
  ///
  /// In en, this message translates to:
  /// **'QC Inspector'**
  String get roleQcInspector;

  /// No description provided for @roleQcShort.
  ///
  /// In en, this message translates to:
  /// **'QC'**
  String get roleQcShort;

  /// No description provided for @roleWorker.
  ///
  /// In en, this message translates to:
  /// **'Worker'**
  String get roleWorker;

  /// No description provided for @roleDriver.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get roleDriver;

  /// No description provided for @roleSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get roleSales;

  /// No description provided for @roleOffice.
  ///
  /// In en, this message translates to:
  /// **'Office'**
  String get roleOffice;

  /// No description provided for @rolePurchasing.
  ///
  /// In en, this message translates to:
  /// **'Purchasing'**
  String get rolePurchasing;

  /// No description provided for @roleParts.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get roleParts;

  /// No description provided for @deptTypeQc.
  ///
  /// In en, this message translates to:
  /// **'QC'**
  String get deptTypeQc;

  /// No description provided for @deptTypeProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get deptTypeProduction;

  /// No description provided for @deptConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{type} • {completion} • Stall {hours}h'**
  String deptConfigSubtitle(String type, String completion, int hours);

  /// No description provided for @deptConfigEditThreshold.
  ///
  /// In en, this message translates to:
  /// **'Edit Threshold'**
  String get deptConfigEditThreshold;

  /// No description provided for @deptConfigWorkflowDiagram.
  ///
  /// In en, this message translates to:
  /// **'Workflow Diagram by Series'**
  String get deptConfigWorkflowDiagram;

  /// No description provided for @deptConfigUpdateFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to update threshold: {msg}'**
  String deptConfigUpdateFail(String msg);

  /// No description provided for @deptConfigEditThresholdTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {code} Stall Threshold'**
  String deptConfigEditThresholdTitle(String code);

  /// No description provided for @deptConfigHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get deptConfigHoursLabel;

  /// No description provided for @createDeliveryLoadFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to load delivery form data: {msg}'**
  String createDeliveryLoadFail(String msg);

  /// No description provided for @createDeliverySingleMode.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get createDeliverySingleMode;

  /// No description provided for @createDeliveryBatchMode.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get createDeliveryBatchMode;

  /// No description provided for @createDeliveryCreateBatch.
  ///
  /// In en, this message translates to:
  /// **'Create Batch'**
  String get createDeliveryCreateBatch;

  /// No description provided for @createDeliveryRecordPickup.
  ///
  /// In en, this message translates to:
  /// **'Record Pickup'**
  String get createDeliveryRecordPickup;

  /// No description provided for @createDeliveryReadyTrailer.
  ///
  /// In en, this message translates to:
  /// **'Ready Trailer'**
  String get createDeliveryReadyTrailer;

  /// No description provided for @createDeliveryTrailerRequired.
  ///
  /// In en, this message translates to:
  /// **'Trailer is required'**
  String get createDeliveryTrailerRequired;

  /// No description provided for @createDeliveryFactoryPickupHelper.
  ///
  /// In en, this message translates to:
  /// **'Recorded as picked up immediately — the customer collects the trailer at the factory.'**
  String get createDeliveryFactoryPickupHelper;

  /// No description provided for @createDeliveryPickedUpBy.
  ///
  /// In en, this message translates to:
  /// **'Picked up by (optional)'**
  String get createDeliveryPickedUpBy;

  /// No description provided for @createDeliveryAmountCollected.
  ///
  /// In en, this message translates to:
  /// **'Amount Collected (optional)'**
  String get createDeliveryAmountCollected;

  /// No description provided for @createDeliveryAssignDriver.
  ///
  /// In en, this message translates to:
  /// **'Assign Driver'**
  String get createDeliveryAssignDriver;

  /// No description provided for @createDeliveryDestinationLocation.
  ///
  /// In en, this message translates to:
  /// **'Destination Location'**
  String get createDeliveryDestinationLocation;

  /// No description provided for @createDeliveryYardHelper.
  ///
  /// In en, this message translates to:
  /// **'Pick a yard, or leave unselected and enter a custom address below.'**
  String get createDeliveryYardHelper;

  /// No description provided for @createDeliveryClearYardAddress.
  ///
  /// In en, this message translates to:
  /// **'Clear yard, use custom address'**
  String get createDeliveryClearYardAddress;

  /// No description provided for @createDeliveryCustomAddress.
  ///
  /// In en, this message translates to:
  /// **'Custom Destination Address'**
  String get createDeliveryCustomAddress;

  /// No description provided for @createDeliveryContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact Phone (optional)'**
  String get createDeliveryContactPhone;

  /// No description provided for @createDeliveryDriverTextsHelper.
  ///
  /// In en, this message translates to:
  /// **'The driver texts this number'**
  String get createDeliveryDriverTextsHelper;

  /// No description provided for @createDeliveryBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'Balance Due'**
  String get createDeliveryBalanceDue;

  /// No description provided for @createDeliveryAddToBatch.
  ///
  /// In en, this message translates to:
  /// **'Add to Existing Batch (optional)'**
  String get createDeliveryAddToBatch;

  /// No description provided for @createDeliveryNoBatch.
  ///
  /// In en, this message translates to:
  /// **'No batch'**
  String get createDeliveryNoBatch;

  /// No description provided for @createDeliveryBatchEntry.
  ///
  /// In en, this message translates to:
  /// **'{batch} ({status})'**
  String createDeliveryBatchEntry(String batch, String status);

  /// No description provided for @createDeliveryBatchNumber.
  ///
  /// In en, this message translates to:
  /// **'Batch Number'**
  String get createDeliveryBatchNumber;

  /// No description provided for @createDeliveryBatchNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Batch number is required'**
  String get createDeliveryBatchNumberRequired;

  /// No description provided for @createDeliveryScheduledDate.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Date'**
  String get createDeliveryScheduledDate;

  /// No description provided for @createDeliveryScheduledPickHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get createDeliveryScheduledPickHint;

  /// No description provided for @createDeliveryBatchType.
  ///
  /// In en, this message translates to:
  /// **'Batch Type'**
  String get createDeliveryBatchType;

  /// No description provided for @createDeliveryBatchTypeDealer.
  ///
  /// In en, this message translates to:
  /// **'Dealer'**
  String get createDeliveryBatchTypeDealer;

  /// No description provided for @createDeliveryBatchTypeBfLocation.
  ///
  /// In en, this message translates to:
  /// **'Bigfoot Location'**
  String get createDeliveryBatchTypeBfLocation;

  /// No description provided for @createDeliveryBatchYardHelper.
  ///
  /// In en, this message translates to:
  /// **'Pick a yard, or leave unselected and enter a destination name below.'**
  String get createDeliveryBatchYardHelper;

  /// No description provided for @createDeliveryClearYardName.
  ///
  /// In en, this message translates to:
  /// **'Clear yard, use custom name'**
  String get createDeliveryClearYardName;

  /// No description provided for @createDeliveryDestinationName.
  ///
  /// In en, this message translates to:
  /// **'Destination Name (for dealers)'**
  String get createDeliveryDestinationName;

  /// No description provided for @createDeliveryTrailersSelected.
  ///
  /// In en, this message translates to:
  /// **'Trailers  ({n} selected)'**
  String createDeliveryTrailersSelected(int n);

  /// No description provided for @createDeliverySelectTrailer.
  ///
  /// In en, this message translates to:
  /// **'Select at least one trailer for the batch.'**
  String get createDeliverySelectTrailer;

  /// No description provided for @createDeliveryNotReady.
  ///
  /// In en, this message translates to:
  /// **'A selected trailer is not ready for delivery'**
  String get createDeliveryNotReady;

  /// No description provided for @createDeliveryNoReadyTrailers.
  ///
  /// In en, this message translates to:
  /// **'No ready-for-delivery trailers available.'**
  String get createDeliveryNoReadyTrailers;

  /// No description provided for @createDeliveryStockedAt.
  ///
  /// In en, this message translates to:
  /// **'Stocked at {value}'**
  String createDeliveryStockedAt(String value);

  /// No description provided for @createDeliveryCreateFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to create: {msg}'**
  String createDeliveryCreateFail(String msg);

  /// No description provided for @batchScreenDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Batch'**
  String get batchScreenDeleteTitle;

  /// No description provided for @batchScreenDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete {batch}? This removes the batch and its {n, plural, =1{1 delivery record} other{{n} delivery records}}. Trailers not yet delivered are returned to the ready-for-delivery pool.'**
  String batchScreenDeleteBody(String batch, int n);

  /// No description provided for @batchScreenDeleted.
  ///
  /// In en, this message translates to:
  /// **'{batch} deleted.'**
  String batchScreenDeleted(String batch);

  /// No description provided for @batchScreenDeleteFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {msg}'**
  String batchScreenDeleteFail(String msg);

  /// No description provided for @batchScreenCompleteFail.
  ///
  /// In en, this message translates to:
  /// **'Failed to complete: {msg}'**
  String batchScreenCompleteFail(String msg);

  /// No description provided for @batchScreenTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type: {value}'**
  String batchScreenTypeLabel(String value);

  /// No description provided for @batchScreenDriverLabel.
  ///
  /// In en, this message translates to:
  /// **'Driver: {value}'**
  String batchScreenDriverLabel(String value);

  /// No description provided for @batchScreenDestinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination: {value}'**
  String batchScreenDestinationLabel(String value);

  /// No description provided for @batchScreenTrailersLabel.
  ///
  /// In en, this message translates to:
  /// **'Trailers: {n}'**
  String batchScreenTrailersLabel(int n);

  /// No description provided for @batchScreenUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update {batch}'**
  String batchScreenUpdateTitle(String batch);

  /// No description provided for @batchScreenDriverField.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get batchScreenDriverField;

  /// No description provided for @batchScreenCustomDestination.
  ///
  /// In en, this message translates to:
  /// **'Custom destination name'**
  String get batchScreenCustomDestination;

  /// No description provided for @batchScreenDestinationName.
  ///
  /// In en, this message translates to:
  /// **'Destination Name'**
  String get batchScreenDestinationName;

  /// No description provided for @batchScreenAddTrailerId.
  ///
  /// In en, this message translates to:
  /// **'Add Trailer ID (optional)'**
  String get batchScreenAddTrailerId;

  /// No description provided for @batchScreenRemoveDeliveryId.
  ///
  /// In en, this message translates to:
  /// **'Remove Delivery ID (optional)'**
  String get batchScreenRemoveDeliveryId;

  /// No description provided for @batchScreenTrailersInBatchLabel.
  ///
  /// In en, this message translates to:
  /// **'Currently in batch ({count})'**
  String batchScreenTrailersInBatchLabel(int count);

  /// No description provided for @batchScreenNoTrailersInBatch.
  ///
  /// In en, this message translates to:
  /// **'No trailers in this batch yet.'**
  String get batchScreenNoTrailersInBatch;

  /// No description provided for @batchScreenRemoveTrailer.
  ///
  /// In en, this message translates to:
  /// **'Remove from batch'**
  String get batchScreenRemoveTrailer;

  /// No description provided for @batchScreenUndoRemove.
  ///
  /// In en, this message translates to:
  /// **'Undo remove'**
  String get batchScreenUndoRemove;

  /// No description provided for @batchScreenAddTrailersLabel.
  ///
  /// In en, this message translates to:
  /// **'Add ready trailers ({count} selected)'**
  String batchScreenAddTrailersLabel(int count);

  /// No description provided for @batchScreenUpdateFail.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String batchScreenUpdateFail(String error);

  /// No description provided for @batchScreenCompletedNote.
  ///
  /// In en, this message translates to:
  /// **'Batch completed — all trailers delivered.'**
  String get batchScreenCompletedNote;

  /// No description provided for @batchScreenUpdate.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get batchScreenUpdate;

  /// No description provided for @stockInventoryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No trailers in stock at any yard.\nPull down to refresh.'**
  String get stockInventoryEmptyBody;

  /// No description provided for @stockInventoryUnknownDate.
  ///
  /// In en, this message translates to:
  /// **'Unknown date'**
  String get stockInventoryUnknownDate;

  /// No description provided for @stockInventoryDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get stockInventoryDelivered;

  /// No description provided for @stockInventoryDeliveredBy.
  ///
  /// In en, this message translates to:
  /// **'Delivered by'**
  String get stockInventoryDeliveredBy;

  /// No description provided for @driverDeliveredOn.
  ///
  /// In en, this message translates to:
  /// **'Delivered {date}'**
  String driverDeliveredOn(String date);
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
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
