// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Bigfoot Trailers';

  @override
  String get appTitleShort => 'Bigfoot';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonLoading => 'Loading';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get commonUser => 'User';

  @override
  String get commonClose => 'Close';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonNone => 'None';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonSet => 'Set';

  @override
  String get commonUndo => 'Undo';

  @override
  String commonFailed(String msg) {
    return 'Failed: $msg';
  }

  @override
  String get commonBack => 'Back';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSubmit => 'Submit';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonOk => 'OK';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navTrailers => 'Trailers';

  @override
  String get navProduction => 'Production';

  @override
  String get navQc => 'QC';

  @override
  String get navPayroll => 'Payroll';

  @override
  String get navDeliveries => 'Deliveries';

  @override
  String get navAdmin => 'Admin';

  @override
  String get navMyQueue => 'My Queue';

  @override
  String get navSettings => 'Settings';

  @override
  String get navMyPoints => 'My Points';

  @override
  String get navMyDeliveries => 'My Deliveries';

  @override
  String get navHelp => 'How to Use';

  @override
  String get connectionConnected => 'Connected';

  @override
  String get connectionConnecting => 'Connecting';

  @override
  String get connectionOffline => 'Offline';

  @override
  String get offlineBanner => 'Offline - real-time updates paused';

  @override
  String get backToExit => 'Press back again to exit';

  @override
  String get loginTitle => 'BIGFOOT TRAILERS';

  @override
  String get loginSubtitle => 'Sign in to continue';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginRememberEmail => 'Remember email';

  @override
  String get loginSignIn => 'Sign In';

  @override
  String get loginPasswordRequired => 'Please enter your password';

  @override
  String get settingsConnectionSection => 'CONNECTION';

  @override
  String get settingsSecuritySection => 'SECURITY';

  @override
  String get settingsAboutSection => 'ABOUT';

  @override
  String get settingsLanguageSection => 'LANGUAGE';

  @override
  String get settingsWebSocketStatus => 'WebSocket Status';

  @override
  String get settingsWebSocketSubtitle => 'Real-time connection';

  @override
  String get settingsPinTitle => 'Require PIN on App Open';

  @override
  String get settingsPinEnabled => 'PIN lock is enabled';

  @override
  String get settingsPinDisabled => 'No PIN required';

  @override
  String get settingsPinSetTitle => 'Set a 4-digit PIN';

  @override
  String get settingsPinSetSubtitle =>
      'You\'ll be asked for this PIN every time you open the app.';

  @override
  String get settingsPinConfirmTitle => 'Confirm PIN';

  @override
  String get settingsPinConfirmSubtitle => 'Re-enter your PIN to confirm.';

  @override
  String get settingsPinMismatch => 'PINs don\'t match. Try again.';

  @override
  String get settingsPinDisableTitle => 'Disable PIN lock';

  @override
  String get settingsPinDisableSubtitle =>
      'Enter your current PIN to turn lock off.';

  @override
  String get settingsPinCancel => 'Cancel';

  @override
  String get settingsAppVersion => 'App Version';

  @override
  String get settingsApiVersion => 'API Version';

  @override
  String get settingsLanguageTitle => 'App Language';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSpanish => 'Spanish';

  @override
  String get settingsSignOut => 'Sign Out';

  @override
  String get settingsSignOutConfirmTitle => 'Sign Out';

  @override
  String get settingsSignOutConfirmMessage =>
      'Are you sure you want to sign out? You will need to sign in again.';

  @override
  String get dashboardGoodMorning => 'Good morning';

  @override
  String get dashboardGoodAfternoon => 'Good afternoon';

  @override
  String get dashboardGoodEvening => 'Good evening';

  @override
  String get authPinTitle => 'Enter PIN';

  @override
  String get authPinSubtitle => 'Enter your 4-digit PIN to unlock';

  @override
  String get authPinIncorrect => 'Incorrect PIN';

  @override
  String get authPinSignOut => 'Sign out instead';

  @override
  String get authSplashTagline => 'Built to haul. Ready to move.';

  @override
  String get dashStatActiveTrailers => 'Active Trailers';

  @override
  String get dashStatReadyForDelivery => 'Ready for Delivery';

  @override
  String get dashStatHotTrailers => 'Hot Trailers';

  @override
  String get dashStatHotBadge => 'HOT';

  @override
  String get dashStatStalledSteps => 'Stalled Steps';

  @override
  String get dashStatCompletedThisWeek => 'Completed This Week';

  @override
  String get dashStatQcFailRate => 'QC Fail Rate';

  @override
  String get dashStatPointsToday => 'Points Today';

  @override
  String get dashStatPointsThisWeek => 'Points This Week';

  @override
  String get dashStatNextTrailer => 'Next Trailer';

  @override
  String get dashStatReadyForInspection => 'Ready for Inspection';

  @override
  String get dashStatInspectionsToday => 'Inspections Today';

  @override
  String get dashStatFailRateToday => 'Fail Rate Today';

  @override
  String get dashStatReworkQueue => 'Rework Queue';

  @override
  String get dashStatScheduled => 'Scheduled';

  @override
  String get dashStatReadyForPickup => 'Ready for Pickup';

  @override
  String get dashStockInventory => 'Stock Inventory';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusInProduction => 'In Production';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusInTransit => 'In Transit';

  @override
  String get statusDelivered => 'Delivered';

  @override
  String get statusOnHold => 'On Hold';

  @override
  String get statusScheduled => 'Scheduled';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusWaiting => 'Waiting';

  @override
  String get statusActive => 'Active';

  @override
  String get statusComplete => 'Complete';

  @override
  String get statusRework => 'Rework';

  @override
  String get saleStatusSold => 'SOLD';

  @override
  String get saleStatusSalePending => 'SALE PENDING';

  @override
  String get saleStatusAvailable => 'Available';

  @override
  String get saleStatusSoldLong => 'Sold';

  @override
  String get saleStatusSalePendingLong => 'Sale Pending';

  @override
  String get trailersSearchHint => 'Search by SO# or customer...';

  @override
  String get trailersFilterHotOnly => 'Hot Only';

  @override
  String get trailersStockBuild => 'Stock Build';

  @override
  String get trailersEmpty => 'No trailers found';

  @override
  String trailersStepIndicator(int step, int total, String dept) {
    return 'Step $step/$total — $dept';
  }

  @override
  String get cacheBannerJustNow => 'just now';

  @override
  String get cacheBannerUnknownTime => 'unknown time';

  @override
  String cacheBannerMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String cacheBannerMessage(String when) {
    return 'Showing cached data. Last updated $when.';
  }

  @override
  String get createTrailerTitle => 'Create Trailer';

  @override
  String get createTrailerSubmit => 'Create Trailer';

  @override
  String get createTrailerModelsEmpty =>
      'No trailer models are configured on the server.';

  @override
  String get createTrailerModelsLoadFail =>
      'Could not load trailer models. Check your connection.';

  @override
  String get createTrailerModelsNone => 'No trailer models available.';

  @override
  String createTrailerModelFallback(String id) {
    return 'Model $id';
  }

  @override
  String get createTrailerPickPdfFail =>
      'Could not read the selected PDF file.';

  @override
  String get createTrailerPickerOpenFail => 'Unable to open the file picker.';

  @override
  String get createTrailerStockDestRequired => 'Pick a stock destination';

  @override
  String createTrailerCreated(String so) {
    return 'Trailer $so created with 12 workflow steps';
  }

  @override
  String createTrailerCreatedPdfWarn(String warning) {
    return 'Trailer created. PDF upload failed: $warning';
  }

  @override
  String get createTrailerFail => 'Failed to create trailer';

  @override
  String get createTrailerPdfRetryLater => 'no network — PDF will retry later';

  @override
  String get createTrailerSoLabel => 'SO Number *';

  @override
  String get createTrailerSoRequired => 'SO number is required';

  @override
  String get createTrailerModelLabel => 'Trailer Model *';

  @override
  String get createTrailerModelRequired => 'Select a trailer model';

  @override
  String get createTrailerColorLabel => 'Color';

  @override
  String get createTrailerSizeLabel => 'Size (ft)';

  @override
  String get createTrailerNotesLabel => 'Options / Notes';

  @override
  String get trailerVinLabel => 'VIN Number';

  @override
  String get trailerVinHint => '17 characters';

  @override
  String get trailerVinInvalid => 'VIN must be 17 characters (no I, O or Q)';

  @override
  String get createTrailerSpecialLabel => 'Special Note';

  @override
  String get createTrailerSpecialHint => 'e.g. ship empty, hold for inspection';

  @override
  String get createTrailerStockBuild => 'Stock Build';

  @override
  String get createTrailerStockBuildSubtitle => 'No customer assigned';

  @override
  String get createTrailerCustomerLabel => 'Customer';

  @override
  String get createTrailerCustomerHint => 'Buyer name — leave blank for stock';

  @override
  String get createTrailerCustomerHelper =>
      'Optional. A trailer with a customer is marked sold.';

  @override
  String get createTrailerStockDestLabel => 'Stock Destination *';

  @override
  String get createTrailerPdfSectionTitle => 'QB Sales Order PDF';

  @override
  String get createTrailerPdfRemoveTooltip => 'Remove PDF';

  @override
  String get createTrailerPdfOptionalHelper =>
      'Optional — attach the QuickBooks SO PDF for this trailer.';

  @override
  String get createTrailerPdfReplace => 'Replace PDF';

  @override
  String get createTrailerPdfAttach => 'Attach PDF';

  @override
  String editTrailerTitle(String so) {
    return 'Edit $so';
  }

  @override
  String get editTrailerSubmit => 'Save Changes';

  @override
  String editTrailerUpdated(String so) {
    return 'Trailer $so updated';
  }

  @override
  String editTrailerUpdatedPdfWarn(String warning) {
    return 'Trailer updated. PDF upload failed: $warning';
  }

  @override
  String get editTrailerFail => 'Failed to update trailer';

  @override
  String get editTrailerPdfDiscardTooltip => 'Discard new PDF';

  @override
  String get editTrailerPdfExisting =>
      'A PDF is already attached. Pick a new file to replace it.';

  @override
  String trailerDetailTitleFallback(int id) {
    return 'Trailer #$id';
  }

  @override
  String get trailerDetailMenuEdit => 'Edit Trailer';

  @override
  String get trailerDetailMenuRemoveHot => 'Remove Hot';

  @override
  String get trailerDetailMenuMarkHot => 'Mark Hot';

  @override
  String get trailerDetailMenuSetPriority => 'Set Priority';

  @override
  String get trailerDetailMenuAddAddon => 'Add Addon';

  @override
  String get trailerDetailMenuViewPdf => 'View QB PDF';

  @override
  String get trailerDetailMenuDelete => 'Delete Trailer';

  @override
  String get trailerDetailTabInfo => 'Info';

  @override
  String get trailerDetailTabWorkflow => 'Workflow';

  @override
  String get trailerDetailTabHistory => 'History';

  @override
  String get trailerDetailTabPhotos => 'Photos';

  @override
  String get trailerDetailDeleteTitle => 'Delete trailer?';

  @override
  String trailerDetailDeleteBody(String so) {
    return 'This permanently deletes $so and ALL related records — production steps, QC inspections, deliveries, photos, addons, and history.\n\nThis cannot be undone.';
  }

  @override
  String get trailerDetailDeleteConfirm => 'Delete';

  @override
  String trailerDetailDeleted(String so) {
    return '$so deleted';
  }

  @override
  String trailerDetailDeleteFailed(String msg) {
    return 'Delete failed: $msg';
  }

  @override
  String get trailerDetailPriorityTitle => 'Set Priority';

  @override
  String get trailerDetailPriorityLabel => 'Priority number';

  @override
  String get trailerDetailPriorityHint => '1 = highest';

  @override
  String get trailerDetailPrioritySet => 'Set';

  @override
  String get trailerDetailAddonTitle => 'Add Addon';

  @override
  String get trailerDetailAddonName => 'Addon name *';

  @override
  String get trailerDetailAddonNotes => 'Notes';

  @override
  String get trailerDetailAddonAdd => 'Add';

  @override
  String trailerDetailUpdateFailed(String msg) {
    return 'Update failed: $msg';
  }

  @override
  String get trailerDetailMarkedSold => 'Trailer marked as sold';

  @override
  String get trailerDetailMarkedSalePending => 'Trailer marked as sale pending';

  @override
  String get trailerDetailMarkedAvailable => 'Trailer marked as available';

  @override
  String get trailerDetailBannerSold => 'SOLD';

  @override
  String get trailerDetailBannerSalePending => 'SALE PENDING';

  @override
  String get trailerDetailBannerAvailable => 'AVAILABLE';

  @override
  String trailerDetailSoldTo(String buyer) {
    return 'Sold to $buyer';
  }

  @override
  String get trailerDetailMarkedSoldShort => 'Marked sold';

  @override
  String get trailerDetailSalePendingDesc =>
      'A sale is in progress for this trailer';

  @override
  String get trailerDetailAvailableDesc =>
      'Not yet sold — available for a customer';

  @override
  String get trailerDetailMarkAvailable => 'Mark Available';

  @override
  String get trailerDetailAvailable => 'Available';

  @override
  String get trailerDetailSalePending => 'Sale Pending';

  @override
  String get trailerDetailSold => 'Sold';

  @override
  String trailerDetailMarkSoldTitle(String so) {
    return 'Mark $so as sold';
  }

  @override
  String get trailerDetailMarkSoldBuyerRequired => 'Enter the buyer\'s name';

  @override
  String get trailerDetailMarkSoldBuyerLabel => 'Buyer name *';

  @override
  String get trailerDetailMarkSoldBuyerHint => 'Who bought this trailer?';

  @override
  String get trailerDetailMarkSoldButton => 'Mark Sold';

  @override
  String get trailerDetailUnknownModel => 'Unknown Model';

  @override
  String get trailerDetailNoCustomer => 'None';

  @override
  String get trailerDetailFieldCustomer => 'Customer';

  @override
  String get trailerDetailFieldColor => 'Color';

  @override
  String get trailerDetailFieldSize => 'Size';

  @override
  String get trailerDetailFieldPriority => 'Priority';

  @override
  String get trailerDetailPriorityDefault => 'Default';

  @override
  String get trailerDetailOpenPdf => 'Open QB PDF';

  @override
  String get trailerDetailNotesLabel => 'Options / Notes';

  @override
  String get trailerDetailSpecialLabel => 'Special Note';

  @override
  String get trailerDetailAddonsTitle => 'Addons';

  @override
  String get trailerDetailDepartmentLabel => 'Department';

  @override
  String get trailerDetailLocationLabel => 'Location';

  @override
  String get trailerDetailStatusReadyForDelivery => 'Ready for delivery';

  @override
  String get trailerDetailStatusInTransit => 'In transit';

  @override
  String get trailerDetailStatusDelivered => 'Delivered';

  @override
  String get trailerDetailStatusOnHold => 'On hold';

  @override
  String get trailerDetailStatusPendingProduction => 'Pending production';

  @override
  String get trailerDetailStatusWorkflowComplete => 'Workflow complete';

  @override
  String get trailerDetailNoSteps => 'No workflow steps';

  @override
  String trailerDetailJumpTitle(int n) {
    return 'Move trailer to step $n?';
  }

  @override
  String trailerDetailJumpBody(String dept) {
    return 'This places the trailer at \"$dept\" as the current active step.\n\n• Earlier steps will be marked complete (no points awarded for any that weren\'t already done).\n• Later steps will be reset to waiting.\n• Each rolled-back step is recorded in the history tab.';
  }

  @override
  String get trailerDetailJumpReasonLabel => 'Reason (optional)';

  @override
  String get trailerDetailJumpReasonHint => 'e.g. wrong step tapped earlier';

  @override
  String get trailerDetailJumpConfirm => 'Move Here';

  @override
  String trailerDetailJumpedTo(String dept) {
    return 'Trailer moved to \"$dept\"';
  }

  @override
  String trailerDetailJumpFailed(String msg) {
    return 'Move failed: $msg';
  }

  @override
  String get trailerDetailCurrentlyActive => 'Currently active';

  @override
  String get trailerDetailMoveBackHere => 'Move trailer back here';

  @override
  String get trailerDetailMoveHere => 'Move trailer here';

  @override
  String get trailerDetailNoHistory => 'No history yet';

  @override
  String get trailerDetailNoPhotos => 'No stage photos available';

  @override
  String trailerDetailReworkBadge(int count) {
    return 'REWORK x$count';
  }

  @override
  String trailerDetailCompletedOn(String when) {
    return 'Completed $when';
  }

  @override
  String trailerDetailPointsAwarded(String pts) {
    return '+$pts pts';
  }

  @override
  String trailerDetailStepLabel(int n) {
    return 'Step $n';
  }

  @override
  String trailerDetailPriorityBadge(int n) {
    return '#$n';
  }

  @override
  String get queueLoading => 'Loading queue...';

  @override
  String get queueDepartmentLabel => 'Department';

  @override
  String get queueTitleFallback => 'Queue';

  @override
  String get queueFilterStalled => 'Stalled';

  @override
  String queueFilterStalledCount(int n) {
    return 'Stalled ($n)';
  }

  @override
  String queueTrailerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trailers',
      one: '1 trailer',
    );
    return '$_temp0';
  }

  @override
  String get queueUndoTitle => 'Undo Completion?';

  @override
  String get queueUndoBody =>
      'This will return the trailer to this department\'s queue.';

  @override
  String get queueReversed => 'Step reversed successfully';

  @override
  String queueReverseFailed(String msg) {
    return 'Failed to reverse: $msg';
  }

  @override
  String get queueEmptyTitle => 'Queue Empty';

  @override
  String get queueEmptyBody => 'No trailers waiting in this department';

  @override
  String get queueNoStalledTitle => 'No Stalled Trailers';

  @override
  String get queueNoStalledBody =>
      'Nothing in this department is past the stall threshold.\nTurn off the \"Stalled\" filter to see the full queue.';

  @override
  String get queueOpenDetailTooltip => 'Open trailer detail';

  @override
  String get queueCompleteButton => 'COMPLETE';

  @override
  String queueMinutesInQueue(int n) {
    return '${n}m in queue';
  }

  @override
  String queueHoursInQueue(String n) {
    return '${n}h in queue';
  }

  @override
  String queueDaysHoursInQueue(int d, int h) {
    return '${d}d ${h}h in queue';
  }

  @override
  String queueReworkBadge(int count) {
    return 'REWORK ×$count';
  }

  @override
  String queueOverlayPoints(String pts) {
    return '+$pts points';
  }

  @override
  String get queueOverlayRework => 'Completed (rework)';

  @override
  String queueOverlayNext(String dept) {
    return 'Next: $dept';
  }

  @override
  String get stepCompleteTitle => 'Complete Step';

  @override
  String get stepChecklistRequired =>
      'Answer every checklist item. Notes are required on any \"No\".';

  @override
  String stepChecklistLoadFail(String msg) {
    return 'Failed to load checklist: $msg';
  }

  @override
  String get stepHotBadge => 'HOT';

  @override
  String get stepDetailModel => 'Model';

  @override
  String get stepDetailCustomer => 'Customer';

  @override
  String get stepDetailColor => 'Color';

  @override
  String get stepDetailSize => 'Size';

  @override
  String get stepDetailNotes => 'Notes';

  @override
  String stepPdfTitle(String so) {
    return '$so — QB Sales Order';
  }

  @override
  String get stepViewQbPdf => 'View QB Sales Order';

  @override
  String get stepFullDetails => 'Full Details';

  @override
  String get stepViewFullDetails => 'View full trailer details';

  @override
  String stepReworkHeader(int count) {
    return 'REWORK — QC Fail Notes (×$count)';
  }

  @override
  String get stepReworkWarning => 'Rework steps award 0 points.';

  @override
  String get stepSelfCheckTitle => 'Self-Check';

  @override
  String get stepSelfCheckHint =>
      'Confirm each item before completing. Notes are required on any \"No\".';

  @override
  String get stepNoteRequired => 'Note (required)';

  @override
  String get stepNotesLabel => 'Completion Notes (optional)';

  @override
  String get stepNotesHint => 'Any notes about this step...';

  @override
  String get stepCompleting => 'Completing...';

  @override
  String get stepCompleteCta => 'COMPLETE STEP';

  @override
  String get stepCompleteSuccessTitle => 'Step Complete!';

  @override
  String get stepReworkSuccessPoints => 'Rework — 0 points';

  @override
  String stepNextDept(String dept) {
    return 'Next → $dept';
  }

  @override
  String get allQueuesTitle => 'All Queues';

  @override
  String get allQueuesLoadFail => 'Failed to load queues';

  @override
  String get allQueuesReorderFail => 'Failed to reorder queue';

  @override
  String get allQueuesEmpty => 'Queue empty';

  @override
  String get qcFilterRework => 'Rework';

  @override
  String qcReadyToInspect(int n) {
    return '$n ready to inspect';
  }

  @override
  String qcInspectionsPending(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n inspections pending',
      one: '1 inspection pending',
    );
    return '$_temp0';
  }

  @override
  String get qcNoReworkTitle => 'No Rework Items';

  @override
  String get qcNoInspectionsTitle => 'Nothing to Inspect';

  @override
  String get qcNoReworkBody => 'No rework inspections in the queue.';

  @override
  String get qcAllInspectedBody => 'All ready inspections are done.';

  @override
  String get qcQueuesClearBody => 'All QC queues are clear.';

  @override
  String get qcSearchHint => 'Search by SO number';

  @override
  String get qcSearchNoMatchTitle => 'No matches';

  @override
  String qcSearchNoMatchBody(String query) {
    return 'No active inspections match \"$query\".';
  }

  @override
  String get qcInfoModel => 'Model';

  @override
  String get qcInfoSize => 'Size';

  @override
  String get qcInfoColor => 'Color';

  @override
  String get qcInfoCustomer => 'Customer';

  @override
  String get qcInfoSaleStatus => 'Sale Status';

  @override
  String get qcInfoOptions => 'Options';

  @override
  String get qcInfoSpecialNote => 'Special Note';

  @override
  String get announcementDefaultTitle => 'Announcement';

  @override
  String announcementPostedBy(String name) {
    return 'Posted by $name';
  }

  @override
  String get announcementsTitle => 'Announcements';

  @override
  String get announcementsNew => 'New Announcement';

  @override
  String get announcementsEmpty => 'No announcements yet.';

  @override
  String get announcementsActive => 'Active';

  @override
  String get announcementsInactive => 'Inactive';

  @override
  String announcementsAckProgress(int acked, int total) {
    return '$acked of $total acknowledged';
  }

  @override
  String get announcementsActivate => 'Activate';

  @override
  String get announcementsDeactivate => 'Deactivate';

  @override
  String get announcementsDeleteTitle => 'Delete announcement?';

  @override
  String get announcementsDeleteBody =>
      'This removes the announcement and all acknowledgement history. Set Active=false instead to keep the trail.';

  @override
  String get announcementsTitleField => 'Title (optional)';

  @override
  String get announcementsBodyField => 'Message';

  @override
  String get announcementsBodyRequired => 'Message is required';

  @override
  String get announcementsNoExpiry => 'No expiry — runs until deactivated';

  @override
  String announcementsExpiresOn(String date) {
    return 'Expires $date';
  }

  @override
  String get announcementsSetExpiry => 'Set expiry';

  @override
  String get announcementsPublish => 'Publish to all users';

  @override
  String get qcEarlierStageFallback => 'an earlier stage';

  @override
  String qcStillAtStage(String so, String stage, String dept) {
    return '$so is still at $stage. Inspect when it reaches $dept.';
  }

  @override
  String qcReadyCount(int n) {
    return '$n ready';
  }

  @override
  String qcUpcomingCount(int n) {
    return '· $n upcoming';
  }

  @override
  String qcCurrentlyAt(String name) {
    return 'Currently at: $name';
  }

  @override
  String get qcUpcomingChip => 'UPCOMING';

  @override
  String get qcAnswerAll => 'Please answer all checklist items';

  @override
  String get qcFillRequired => 'Please fill all required fields';

  @override
  String qcInspectTitle(String so) {
    return 'Inspect $so';
  }

  @override
  String get qcSubmittingInspection => 'Submitting inspection...';

  @override
  String get qcStep1Title => 'Step 1: Photos';

  @override
  String get qcStep1Subtitle => 'Photos are optional';

  @override
  String get qcStep1PendingUploads =>
      'Please wait for pending uploads to finish before continuing';

  @override
  String get qcInspectionPhotos => 'QC Inspection Photos';

  @override
  String get qcNextChecklist => 'Next: Checklist';

  @override
  String get qcStep2Title => 'Step 2: Checklist';

  @override
  String get qcChecklistNotConfigured =>
      'No checklist items configured for this department';

  @override
  String get qcChecklistLoadFail => 'Could not load checklist';

  @override
  String get qcNextResult => 'Next: Result';

  @override
  String qcAnsweredOf(int n, int total) {
    return '$n of $total';
  }

  @override
  String get qcOptionalNote => 'Optional note...';

  @override
  String get qcPass => 'PASS';

  @override
  String get qcFail => 'FAIL';

  @override
  String get qcWorker => 'Worker';

  @override
  String qcUpstreamMarkedPrefix(String who, String dept) {
    return '$who$dept marked ';
  }

  @override
  String qcUpstreamFailedCount(int f, int t) {
    return 'Upstream self-checks: $f failed of $t';
  }

  @override
  String qcUpstreamAllPassed(int n) {
    return 'All $n upstream self-checks passed';
  }

  @override
  String get qcStep3Title => 'Step 3: Inspection Result';

  @override
  String get qcStep3Subtitle => 'Select the final inspection result';

  @override
  String get qcFinalQcWarning =>
      'FINAL QC — Passing will mark trailer as Ready for Delivery';

  @override
  String get qcSubmitInspection => 'Submit Inspection';

  @override
  String get qcNextFailDetails => 'Next: Fail Details';

  @override
  String get qcStep4Title => 'Step 4: Fail Details';

  @override
  String get qcStep4Subtitle =>
      'Describe the defect and select rework department';

  @override
  String get qcFailNotesLabel => 'Fail Notes *';

  @override
  String get qcFailNotesHint => 'Describe what failed and needs to be fixed...';

  @override
  String get qcReworkTargetLabel => 'Rework Target Department *';

  @override
  String get qcSelectDept => 'Select department...';

  @override
  String qcInsertedAtPriorityOne(String dept) {
    return 'This trailer will be inserted at #1 priority in $dept\'s queue';
  }

  @override
  String get qcTheSelectedDept => 'the selected department';

  @override
  String get qcResultPassed => 'QC PASSED';

  @override
  String get qcResultFailed => 'QC FAILED';

  @override
  String get qcReadyForDelivery => 'Trailer Ready for Delivery!';

  @override
  String get qcSmsSent => 'SMS Sent';

  @override
  String get qcSendSms => 'Send Customer SMS';

  @override
  String get qcCustomerSmsSent => 'Customer SMS sent';

  @override
  String qcSmsFailed(String msg) {
    return 'SMS failed: $msg';
  }

  @override
  String get qcSmsFailedRetry => 'SMS failed — please retry';

  @override
  String qcReworkSentTo(String dept, int pos) {
    return 'Rework sent to $dept at Priority #$pos';
  }

  @override
  String get qcManagersNotified => 'Production managers have been notified';

  @override
  String get qcInspectionLoadFail => 'Failed to load inspection';

  @override
  String qcInspectionTitle(int id) {
    return 'Inspection #$id';
  }

  @override
  String get qcStatusPassed => 'PASSED';

  @override
  String get qcStatusFailed => 'FAILED';

  @override
  String qcAttemptNumber(int n) {
    return 'Attempt #$n';
  }

  @override
  String get qcFailNotesHeader => 'Fail Notes';

  @override
  String qcPhotosCount(int n) {
    return 'Photos ($n)';
  }

  @override
  String qcChecklistCount(int n) {
    return 'Checklist ($n items)';
  }

  @override
  String qcItemNumber(int id) {
    return 'Item #$id';
  }

  @override
  String qcPhotoNumber(int n) {
    return 'Photo $n';
  }

  @override
  String get qcMgmtLoadFail => 'Failed to load checklist items';

  @override
  String get qcMgmtAddTitle => 'Add Checklist Item';

  @override
  String get qcMgmtDeptLabel => 'QC Department';

  @override
  String get qcMgmtLabelField => 'Label';

  @override
  String get qcMgmtSortOrder => 'Sort Order';

  @override
  String get qcMgmtSeriesLabel => 'Applies To Series';

  @override
  String get qcMgmtAllSeries => 'All Series';

  @override
  String qcMgmtCreateFail(String msg) {
    return 'Failed to create: $msg';
  }

  @override
  String get qcMgmtEditTitle => 'Edit Checklist Item';

  @override
  String get qcMgmtDeactivate => 'Deactivate';

  @override
  String get qcMgmtScreenTitle => 'QC Checklist Items';

  @override
  String get qcMgmtEmpty => 'No checklist items';

  @override
  String qcMgmtSeriesValue(String series) {
    return 'Series: $series';
  }

  @override
  String qcMgmtSeriesValueInactive(String series) {
    return 'Series: $series (inactive)';
  }

  @override
  String qcMgmtDeptFallback(int id) {
    return 'Dept $id';
  }

  @override
  String get payrollWeeklyReport => 'Weekly Report';

  @override
  String get payrollPointMatrix => 'Point Matrix';

  @override
  String get payrollDollarRates => 'Dollar Rates';

  @override
  String get payrollCurrentWeekSummary => 'Current Week Summary';

  @override
  String get payrollTotalPoints => 'Total Points';

  @override
  String get payrollProjected => 'Projected';

  @override
  String get payrollSteps => 'Steps';

  @override
  String payrollReworks(int n) {
    return 'Reworks: $n';
  }

  @override
  String get payrollDailyBreakdown => 'Daily Breakdown (Sun-Sat)';

  @override
  String get payrollDaySun => 'Sun';

  @override
  String get payrollDayMon => 'Mon';

  @override
  String get payrollDayTue => 'Tue';

  @override
  String get payrollDayWed => 'Wed';

  @override
  String get payrollDayThu => 'Thu';

  @override
  String get payrollDayFri => 'Fri';

  @override
  String get payrollDaySat => 'Sat';

  @override
  String get payrollEstimated => 'Estimated from available API data';

  @override
  String get payrollDeptBreakdown => 'Department Breakdown';

  @override
  String get payrollDeptEmpty => 'No department activity this week';

  @override
  String payrollPtsSuffix(String n) {
    return '$n pts';
  }

  @override
  String get payrollHistory => 'History';

  @override
  String get payrollHistoryNoAccess =>
      'History endpoint is manager-only in current API permissions';

  @override
  String get payrollHistoryEmpty => 'No historical records found';

  @override
  String get payrollDepartmentFallback => 'Department';

  @override
  String get payrollWeeklyReportTitle => 'Weekly Payroll Report';

  @override
  String get payrollLockTitle => 'Lock Payroll Week';

  @override
  String payrollLockBody(String date) {
    return 'Lock payroll for $date? This cannot be undone.';
  }

  @override
  String get payrollLockConfirm => 'Lock';

  @override
  String get payrollWeekLocked => 'Payroll week locked';

  @override
  String get payrollAlreadyLocked => 'Already locked';

  @override
  String get payrollDateMustBeSunday => 'Date must be a Sunday';

  @override
  String payrollLockFailed(String msg) {
    return 'Failed to lock week: $msg';
  }

  @override
  String payrollCsvPrepared(int n) {
    return 'CSV prepared ($n chars)';
  }

  @override
  String get payrollCsvChooseTitle => 'Export weekly report';

  @override
  String get payrollCsvShare => 'Share';

  @override
  String get payrollCsvShareSub => 'Send via apps, email, or Files';

  @override
  String get payrollCsvSave => 'Save to device';

  @override
  String get payrollCsvSaveSub => 'Choose where to store the .csv';

  @override
  String get payrollCsvSaved => 'CSV saved to device';

  @override
  String payrollCsvExportFail(String msg) {
    return 'CSV export failed: $msg';
  }

  @override
  String get payrollWeekIsLocked => 'Week is locked';

  @override
  String get payrollExportCsv => 'Export CSV';

  @override
  String get payrollLockWeek => 'Lock Week';

  @override
  String get payrollColName => 'Name';

  @override
  String get payrollColPoints => 'Points';

  @override
  String get payrollColReworks => 'Reworks';

  @override
  String get payrollColGross => 'Gross';

  @override
  String payrollTotals(String points, String gross) {
    return 'Totals: $points points • \$ $gross';
  }

  @override
  String get payrollPmTitle => 'Point Values Matrix';

  @override
  String get payrollPmAddTooltip => 'Add point value';

  @override
  String get payrollPmNoData =>
      'No production departments or trailer models are configured yet.';

  @override
  String get payrollPmTapCell => 'Tap any cell to set or edit its points.';

  @override
  String get payrollPmDept => 'Department';

  @override
  String payrollPmLoadFail(String msg) {
    return 'Could not load the point matrix.\n$msg';
  }

  @override
  String get payrollPmNotLoaded =>
      'Departments and trailer models not loaded yet.';

  @override
  String get payrollPmAddTitle => 'Add Point Value';

  @override
  String get payrollPmTrailerModel => 'Trailer Model';

  @override
  String get payrollPmSelectDept => 'Select a department';

  @override
  String get payrollPmSelectModel => 'Select a trailer model';

  @override
  String get payrollPmPointsLabel => 'Points';

  @override
  String payrollPmEffective(String date) {
    return 'Effective: $date';
  }

  @override
  String payrollPmAddFail(String msg) {
    return 'Failed to add point value: $msg';
  }

  @override
  String get payrollPmSetTitle => 'Set Point Value';

  @override
  String get payrollPmEditTitle => 'Edit Point Value';

  @override
  String payrollPmSaveFail(String msg) {
    return 'Failed to save: $msg';
  }

  @override
  String get payrollDrTitle => 'Dollar Rates';

  @override
  String get payrollDrEmpty => 'No dollar rates yet. Tap + to add one.';

  @override
  String payrollDrDeptFallback(int id) {
    return 'Department $id';
  }

  @override
  String payrollDrCurrent(String rate) {
    return 'Current: \$ $rate / point';
  }

  @override
  String payrollDrRatePerPoint(String rate) {
    return '\$ $rate / point';
  }

  @override
  String payrollDrFromTo(String start, String end) {
    return 'From $start to $end';
  }

  @override
  String get payrollDrPresent => 'present';

  @override
  String get payrollDrDeptsNotLoaded =>
      'Departments not loaded yet. Try again.';

  @override
  String get payrollDrAddTitle => 'Add Dollar Rate';

  @override
  String get payrollDrDollarLabel => 'Dollar per Point';

  @override
  String get payrollDrValidNumber => 'Enter a valid positive number';

  @override
  String payrollDrAddFail(String msg) {
    return 'Failed to add rate: $msg';
  }

  @override
  String get payrollDrDeleteTitle => 'Delete dollar rate?';

  @override
  String payrollDrDeleteBody(String rate, String dept) {
    return 'Remove the \$$rate/point rate for $dept? This cannot be undone.';
  }

  @override
  String payrollDrDeleteFail(String msg) {
    return 'Failed to delete rate: $msg';
  }

  @override
  String get customersTitle => 'Customers';

  @override
  String customersLoadFail(String msg) {
    return 'Unable to load customers: $msg';
  }

  @override
  String get customersSearchHint => 'Search name or company';

  @override
  String get customersFilterType => 'Type';

  @override
  String get customersFilterAll => 'All';

  @override
  String get customerTypeEndUser => 'End User';

  @override
  String get customerTypeDealer => 'Dealer';

  @override
  String get customerTypeStockLoc => 'Stock Loc';

  @override
  String get customerTypeStockLocation => 'Stock Location';

  @override
  String get customerTypeStockShort => 'Stock';

  @override
  String customersActiveTrailers(int n) {
    return 'Active trailers: $n';
  }

  @override
  String get customersPrev => 'Prev';

  @override
  String get customersNext => 'Next';

  @override
  String customersPageOf(int n, int total) {
    return 'Page $n / $total';
  }

  @override
  String get customersNew => 'New Customer';

  @override
  String get customerFormCreateTitle => 'Create Customer';

  @override
  String get customerFormEditTitle => 'Edit Customer';

  @override
  String get customerFormName => 'Name *';

  @override
  String get customerFormCompany => 'Company';

  @override
  String get customerFormType => 'Customer Type';

  @override
  String get customerFormPhone => 'Phone';

  @override
  String get customerFormEmail => 'Email';

  @override
  String get customerFormBilling => 'Billing Address';

  @override
  String get customerFormDelivery => 'Delivery Address';

  @override
  String get customerFormSmsOptOut => 'SMS Opt-out';

  @override
  String get customerFormNotes => 'Notes';

  @override
  String get customerFormSaveChanges => 'Save Changes';

  @override
  String customerFormSaveFail(String msg) {
    return 'Failed to save customer: $msg';
  }

  @override
  String get customerDetailTitle => 'Customer Detail';

  @override
  String customerDetailLoadFail(String msg) {
    return 'Unable to load customer detail: $msg';
  }

  @override
  String get customerDetailDeleteTooltip => 'Delete customer';

  @override
  String get customerDetailTabTrailers => 'Trailer History';

  @override
  String get customerDetailTabDeliveries => 'Delivery History';

  @override
  String get customerDetailNotFound => 'Customer not found';

  @override
  String get customerDetailDeleteTitle => 'Delete customer?';

  @override
  String customerDetailDeleteBody(String name) {
    return 'This permanently deletes \"$name\".';
  }

  @override
  String get customerDetailHasTrailersTitle => 'Customer has trailers';

  @override
  String customerDetailHasTrailersBody(String name, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n trailers',
      one: '1 trailer',
    );
    return '\"$name\" is referenced by $_temp0.\n\nDeleting the customer will also delete every associated trailer along with its production history, QC inspections, photos, deliveries, and messages.\n\nThis cannot be undone.';
  }

  @override
  String customerDetailDeleteCascade(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n trailers',
      one: '1 trailer',
    );
    return 'Delete customer + $_temp0';
  }

  @override
  String customerDetailDeletedCascade(String name, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n trailers',
      one: '1 trailer',
    );
    return 'Deleted \"$name\" and $_temp0';
  }

  @override
  String customerDetailDeleted(String name) {
    return 'Deleted customer \"$name\"';
  }

  @override
  String customerDetailDeleteFailed(String msg) {
    return 'Failed to delete: $msg';
  }

  @override
  String customerDetailSmsUpdateFailed(String msg) {
    return 'Failed to update SMS preference: $msg';
  }

  @override
  String customerDetailPhone(String value) {
    return 'Phone: $value';
  }

  @override
  String customerDetailEmail(String value) {
    return 'Email: $value';
  }

  @override
  String customerDetailQbId(String value) {
    return 'QuickBooks ID: $value';
  }

  @override
  String get customerDetailUpdating => 'Updating...';

  @override
  String customerDetailBilling(String value) {
    return 'Billing Address: $value';
  }

  @override
  String customerDetailDelivery(String value) {
    return 'Delivery Address: $value';
  }

  @override
  String customerDetailNotes(String value) {
    return 'Notes: $value';
  }

  @override
  String get customerDetailNoTrailerHistory => 'No trailer history';

  @override
  String get customerDetailNoDeliveryHistory => 'No delivery history';

  @override
  String customerDetailVin(String value) {
    return 'VIN: $value';
  }

  @override
  String customerDetailStatusValue(String value) {
    return 'Status: $value';
  }

  @override
  String get customerDetailOpen => 'Open';

  @override
  String customerDetailDeliveryHash(int id) {
    return 'Delivery #$id';
  }

  @override
  String customerDetailTrailerValue(String value) {
    return 'Trailer: $value';
  }

  @override
  String customerDetailTypeStatus(String type, String status) {
    return 'Type: $type • Status: $status';
  }

  @override
  String get notificationsTitle => 'Notification Center';

  @override
  String get notificationsMarkAllRead => 'Mark all read';

  @override
  String get notificationsEmpty => 'No notifications yet';

  @override
  String get notificationsDelete => 'Delete';

  @override
  String messagesTitle(int id) {
    return 'Trailer #$id Messages';
  }

  @override
  String get messagesRecipientLabel => 'Recipient User ID';

  @override
  String messagesUserFallback(int id) {
    return 'User $id';
  }

  @override
  String get messagesHint => 'Message...';

  @override
  String get messagesSend => 'Send';

  @override
  String messagesSendFail(String msg) {
    return 'Failed to send message: $msg';
  }

  @override
  String get notificationPanelTitle => 'Notifications';

  @override
  String get deliveryListTabScheduled => 'Scheduled';

  @override
  String get deliveryListTabCompleted => 'Completed';

  @override
  String get deliveryListTabFailed => 'Failed';

  @override
  String get deliveryListFabBatches => 'Batches';

  @override
  String get deliveryListFabCreate => 'Create Delivery';

  @override
  String get deliveryListEmpty => 'No deliveries found';

  @override
  String get deliveryListSearchHint => 'Search by SO# or customer...';

  @override
  String get deliveryListSearchEmpty => 'No deliveries match your search';

  @override
  String get deliveryListFilterType => 'Delivery Type';

  @override
  String get deliveryListFilterAllTypes => 'All Types';

  @override
  String get deliveryListFilterFactoryPickup => 'Factory Pickup';

  @override
  String get deliveryListFilterSinglePull => 'Single Pull';

  @override
  String get deliveryListFilterStackToDealer => 'Stack to Dealer';

  @override
  String get deliveryListFilterStackToLocation => 'Stack to Location';

  @override
  String get deliveryListFilterDriverId => 'Driver ID';

  @override
  String get deliveryListFilterDateRange => 'Date Range';

  @override
  String get deliveryListFilterClearDates => 'Clear Dates';

  @override
  String deliveryListBatchTitle(int n) {
    return 'Batch delivery — $n trailers';
  }

  @override
  String deliveryListDestination(String value) {
    return 'Destination: $value';
  }

  @override
  String deliveryListDriverLabel(String value) {
    return 'Driver: $value';
  }

  @override
  String deliveryListScheduled(String value) {
    return 'Scheduled: $value';
  }

  @override
  String deliveryDetailTitle(int id) {
    return 'Delivery #$id';
  }

  @override
  String get deliveryDetailNotFound => 'Delivery not found';

  @override
  String get deliveryDetailDeleteTooltip => 'Delete delivery';

  @override
  String get deliveryDetailSectionTrailer => 'Trailer';

  @override
  String get deliveryDetailSectionDriver => 'Driver';

  @override
  String get deliveryDetailSectionDestination => 'Destination';

  @override
  String get deliveryDetailSectionBalance => 'Balance Due';

  @override
  String get deliveryDetailSectionPickedUp => 'Picked Up By';

  @override
  String get deliveryDetailSectionFailReason => 'Failure Reason';

  @override
  String deliveryDetailSo(String value) {
    return 'SO: $value';
  }

  @override
  String deliveryDetailModel(String value) {
    return 'Model: $value';
  }

  @override
  String deliveryDetailCustomer(String value) {
    return 'Customer: $value';
  }

  @override
  String deliveryDetailAssigned(String value) {
    return 'Assigned: $value';
  }

  @override
  String get deliveryDetailOpenMaps => 'Open in Maps';

  @override
  String get deliveryDetailTextCustomer => 'Text Customer';

  @override
  String get deliveryDetailCompleteAction => 'Complete Delivery';

  @override
  String get deliveryDetailMarkFailed => 'Mark Failed';

  @override
  String get deliveryDetailNoAddress =>
      'No destination address for this delivery.';

  @override
  String get deliveryDetailNoPhone =>
      'No phone number on file for this customer.';

  @override
  String deliveryDetailCompleteFail(String msg) {
    return 'Failed to complete delivery: $msg';
  }

  @override
  String get deliveryDetailCompleteBatchTitle => 'Complete Batch';

  @override
  String deliveryDetailCompleteBatchBody(int n, String batch) {
    return 'Mark all $n trailer(s) in $batch as delivered? This completes the whole batch in one step.';
  }

  @override
  String get deliveryDetailMarkAllDelivered => 'Mark All Delivered';

  @override
  String deliveryDetailBatchAllDelivered(String batch) {
    return '$batch — all trailers delivered.';
  }

  @override
  String deliveryDetailBatchFail(String msg) {
    return 'Failed to complete batch: $msg';
  }

  @override
  String get deliveryDetailDeleteTitle => 'Delete Delivery';

  @override
  String deliveryDetailDeleteBody(String so) {
    return 'Delete this delivery for $so? The trailer goes back to ready for delivery. This cannot be undone.';
  }

  @override
  String deliveryDetailDeleted(String so) {
    return '$so delivery deleted.';
  }

  @override
  String deliveryDetailDeleteFail(String msg) {
    return 'Failed to delete delivery: $msg';
  }

  @override
  String get deliveryDetailMarkFailedTitle => 'Mark Delivery Failed';

  @override
  String deliveryDetailMarkFailedError(String msg) {
    return 'Failed to mark failed: $msg';
  }

  @override
  String get deliveryDetailStatusLabel => 'Status';

  @override
  String deliveryDetailTrailerCount(int n) {
    return '$n trailers';
  }

  @override
  String deliveryDetailBatchTitle(String batch) {
    return 'Batch — $batch';
  }

  @override
  String deliveryDetailBatchStatus(String value) {
    return 'Status: $value';
  }

  @override
  String get deliveryDetailUnassigned => 'Unassigned';

  @override
  String get deliveryDetailCompleteEntireBatch => 'Complete Entire Batch';

  @override
  String get driverDeliveriesTitle => 'My Deliveries';

  @override
  String driverDeliveriesLoadFail(String msg) {
    return 'Failed to load deliveries: $msg';
  }

  @override
  String driverCompleteBatchBody(int n, String batch, String dest) {
    return 'Confirm all $n trailer(s) in $batch were delivered to $dest.';
  }

  @override
  String get driverCompleteTrailerTitle => 'Complete Trailer';

  @override
  String driverCompleteTrailerBody(String so) {
    return 'Mark $so as delivered? Other trailers in the batch stay in transit.';
  }

  @override
  String get driverMarkDelivered => 'Mark Delivered';

  @override
  String driverTrailerDelivered(String so) {
    return '$so delivered.';
  }

  @override
  String driverMarkSoFailed(String so) {
    return 'Mark $so Failed';
  }

  @override
  String driverSoMarkedFailed(String so) {
    return '$so marked failed.';
  }

  @override
  String get driverTheDestination => 'the destination';

  @override
  String get driverCompletedToday => 'Completed Today';

  @override
  String get createDeliveryTitle => 'Create Delivery';

  @override
  String get createDeliverySubmit => 'Create Delivery';

  @override
  String get createDeliveryCreated => 'Delivery created';

  @override
  String createDeliveryFail(String msg) {
    return 'Failed to create delivery: $msg';
  }

  @override
  String get batchScreenTitle => 'Delivery Batches';

  @override
  String get batchScreenEmpty => 'No batches yet. Tap + to create one.';

  @override
  String get batchScreenNewBatch => 'New Batch';

  @override
  String batchCreateFail(String msg) {
    return 'Failed to create batch: $msg';
  }

  @override
  String get stockInventoryTitle => 'Stock Inventory';

  @override
  String get stockInventoryEmpty => 'No stock trailers found.';

  @override
  String stockInventoryLoadFail(String msg) {
    return 'Failed to load stock inventory: $msg';
  }

  @override
  String get completeDeliveryDialogTitle => 'Complete Delivery';

  @override
  String get completeDeliveryPaymentLabel => 'Payment Collected';

  @override
  String get completeDeliveryConfirm => 'Complete';

  @override
  String get failReasonDialogLabel => 'Reason';

  @override
  String get failReasonDialogHint => 'Why did this delivery fail?';

  @override
  String get failReasonRequired => 'A reason is required';

  @override
  String get adminDashboardTitle => 'Admin Panel';

  @override
  String get adminStatTotalUsers => 'Total Users';

  @override
  String get adminStatActiveTrailers => 'Active Trailers';

  @override
  String get adminStatWeeklyOutput => 'Weekly Output';

  @override
  String get adminStatQcFailRate => 'QC Fail Rate';

  @override
  String get adminNavUsersSubtitle =>
      'Create/edit/deactivate users and filter by role';

  @override
  String get adminNavDeptsSubtitle =>
      'Edit stall thresholds and inspect workflow mapping';

  @override
  String get adminNavWorkflowSubtitle => 'View 4 trailer series template steps';

  @override
  String get adminNavAuditSubtitle =>
      'Paginated events with before/after changes';

  @override
  String get adminNavReportsSubtitle =>
      'Weekly summary and worker output overview';

  @override
  String get adminNavAnnouncementsSubtitle =>
      'Push a message every user must acknowledge';

  @override
  String get adminNavReports => 'Production Reports';

  @override
  String get adminNavWorkflowTemplates => 'Workflow Templates';

  @override
  String get adminUsers => 'User Management';

  @override
  String get adminAuditLog => 'Audit Log';

  @override
  String get adminReports => 'Reports';

  @override
  String get adminDepartmentConfig => 'Department Config';

  @override
  String get adminWorkflow => 'Workflow Viewer';

  @override
  String get adminChecklists => 'QC Checklists';

  @override
  String get auditLogTitle => 'Audit Log';

  @override
  String get auditLogEmpty => 'No audit entries';

  @override
  String auditLogLoadFail(String msg) {
    return 'Failed to load audit log: $msg';
  }

  @override
  String get reportsTitle => 'Reports';

  @override
  String reportsLoadFail(String msg) {
    return 'Failed to load reports: $msg';
  }

  @override
  String get userMgmtTitle => 'User Management';

  @override
  String get userMgmtAdd => 'Add User';

  @override
  String get userMgmtEdit => 'Edit User';

  @override
  String get userMgmtDeactivate => 'Deactivate';

  @override
  String get userMgmtReactivate => 'Reactivate';

  @override
  String get userMgmtEmpty => 'No users yet';

  @override
  String userMgmtLoadFail(String msg) {
    return 'Failed to load users: $msg';
  }

  @override
  String userMgmtSaveFail(String msg) {
    return 'Failed to save user: $msg';
  }

  @override
  String get deptConfigTitle => 'Department Config';

  @override
  String get deptConfigEmpty => 'No departments configured';

  @override
  String deptConfigLoadFail(String msg) {
    return 'Failed to load departments: $msg';
  }

  @override
  String get workflowViewerTitle => 'Workflow Viewer';

  @override
  String get photoCaptureTakePhoto => 'Take photo';

  @override
  String get photoCaptureFromGallery => 'From gallery';

  @override
  String get photoCaptureRemove => 'Remove';

  @override
  String get photoCaptureUploading => 'Uploading...';

  @override
  String get photoCaptureFailed => 'Upload failed';

  @override
  String get imageViewerTitle => 'Photo';

  @override
  String get pdfViewerTitle => 'PDF';

  @override
  String get pdfViewerLoadFail => 'Failed to load PDF';

  @override
  String get stockLocationChipsLabel => 'Stock Destination';

  @override
  String get stockLocationChipsLoading => 'Loading locations...';

  @override
  String get stockLocationChipsLoadFail => 'Failed to load locations';

  @override
  String get adminAuditEntityType => 'Entity Type';

  @override
  String get adminAuditEntityTrailer => 'Trailer';

  @override
  String get adminAuditEntityStep => 'Production Step';

  @override
  String get adminAuditEntityQcInspection => 'QC Inspection';

  @override
  String get adminAuditEntityDelivery => 'Delivery';

  @override
  String get adminAuditEntityPayroll => 'Payroll';

  @override
  String get adminAuditEntityUser => 'User';

  @override
  String get adminAuditUserIdLabel => 'User ID';

  @override
  String get adminAuditEmptyMessage =>
      'No audit log entries match these filters.';

  @override
  String get adminPullToRefresh => 'Pull down to refresh.';

  @override
  String get adminAuditOldValues => 'Old Values';

  @override
  String get adminAuditNewValues => 'New Values';

  @override
  String get adminReportsNoReport => 'No report';

  @override
  String get adminReportWeeklySteps => 'Weekly Steps Completed';

  @override
  String get adminReportWeeklyPoints => 'Weekly Points';

  @override
  String get adminReportQcFailTrend => 'QC Fail Trend';

  @override
  String get adminReportAvgTimePerStep => 'Avg Time Per Step';

  @override
  String get adminReportStalledTrailers => 'Stalled Trailers';

  @override
  String get adminReportNotAvailable => 'N/A (endpoint not available)';

  @override
  String get adminReportUseProdDashboard =>
      'Use production dashboard queue view';

  @override
  String get adminReportWorkerSummary => 'Worker Summary';

  @override
  String adminReportRoleValue(String role) {
    return 'Role: $role';
  }

  @override
  String adminReportStepsPtsLine(String steps, String pts) {
    return '$steps steps\n$pts pts';
  }

  @override
  String get userMgmtSearchHint => 'Search name or email';

  @override
  String get userMgmtFilterRole => 'Role';

  @override
  String get userMgmtFilterStatus => 'Status';

  @override
  String get userMgmtInactive => 'Inactive';

  @override
  String get userMgmtEmptyFiltered =>
      'No registered users found for the current filters.';

  @override
  String userMgmtIdChip(int id) {
    return 'ID: $id';
  }

  @override
  String userMgmtDeptChip(String value) {
    return 'Dept: $value';
  }

  @override
  String userMgmtLocationChip(String value) {
    return 'Location: $value';
  }

  @override
  String userMgmtCreatedChip(String value) {
    return 'Created: $value';
  }

  @override
  String get userMgmtNotAvailable => 'N/A';

  @override
  String get userMgmtDeactivateTitle => 'Deactivate user?';

  @override
  String userMgmtDeactivateBody(String name) {
    return '$name will lose access immediately but their history is preserved. You can reactivate later.';
  }

  @override
  String userMgmtDeactivated(String name) {
    return '$name deactivated';
  }

  @override
  String userMgmtReactivated(String name) {
    return '$name reactivated';
  }

  @override
  String get userMgmtDeleteTitle => 'Permanently delete user?';

  @override
  String userMgmtDeleteBody(String name) {
    return 'This permanently removes $name from the database. This cannot be undone.';
  }

  @override
  String get userMgmtDeleteHelper =>
      'The user must be deactivated first. Users with historical activity (completed steps, inspections, deliveries, messages) cannot be deleted — keep them deactivated to preserve the audit trail.';

  @override
  String get userMgmtDeleteForever => 'Delete forever';

  @override
  String userMgmtDeleted(String name) {
    return '$name deleted';
  }

  @override
  String userMgmtDeleteFail(String msg) {
    return 'Delete failed: $msg';
  }

  @override
  String get userMgmtCreateAction => 'Create';

  @override
  String get userMgmtNameLabel => 'Name';

  @override
  String get userMgmtPasswordOptional => 'Password (optional)';

  @override
  String get userMgmtPhoneOptional => 'Phone (optional)';

  @override
  String get userMgmtDeptIdLabel => 'Primary Department';

  @override
  String get userMgmtLocationIdLabel => 'Primary Location';

  @override
  String get userMgmtDeptNone => 'None';

  @override
  String get userMgmtLocationNone => 'N/A';

  @override
  String get roleOwner => 'Owner';

  @override
  String get roleProductionManager => 'Production Manager';

  @override
  String get roleProductionManagerShort => 'Prod Mgr';

  @override
  String get roleTransportManager => 'Transport Manager';

  @override
  String get roleTransportManagerShort => 'Transport Mgr';

  @override
  String get roleQcInspector => 'QC Inspector';

  @override
  String get roleQcShort => 'QC';

  @override
  String get roleWorker => 'Worker';

  @override
  String get roleDriver => 'Driver';

  @override
  String get roleSales => 'Sales';

  @override
  String get roleOffice => 'Office';

  @override
  String get rolePurchasing => 'Purchasing';

  @override
  String get roleParts => 'Parts';

  @override
  String get deptTypeQc => 'QC';

  @override
  String get deptTypeProduction => 'Production';

  @override
  String deptConfigSubtitle(String type, String completion, int hours) {
    return '$type • $completion • Stall ${hours}h';
  }

  @override
  String get deptConfigEditThreshold => 'Edit Threshold';

  @override
  String get deptConfigWorkflowDiagram => 'Workflow Diagram by Series';

  @override
  String deptConfigUpdateFail(String msg) {
    return 'Failed to update threshold: $msg';
  }

  @override
  String deptConfigEditThresholdTitle(String code) {
    return 'Edit $code Stall Threshold';
  }

  @override
  String get deptConfigHoursLabel => 'Hours';

  @override
  String createDeliveryLoadFail(String msg) {
    return 'Failed to load delivery form data: $msg';
  }

  @override
  String get createDeliverySingleMode => 'Single';

  @override
  String get createDeliveryBatchMode => 'Batch';

  @override
  String get createDeliveryCreateBatch => 'Create Batch';

  @override
  String get createDeliveryRecordPickup => 'Record Pickup';

  @override
  String get createDeliveryReadyTrailer => 'Ready Trailer';

  @override
  String get createDeliveryTrailerRequired => 'Trailer is required';

  @override
  String get createDeliveryFactoryPickupHelper =>
      'Recorded as picked up immediately — the customer collects the trailer at the factory.';

  @override
  String get createDeliveryPickedUpBy => 'Picked up by (optional)';

  @override
  String get createDeliveryAmountCollected => 'Amount Collected (optional)';

  @override
  String get createDeliveryAssignDriver => 'Assign Driver';

  @override
  String get createDeliveryDestinationLocation => 'Destination Location';

  @override
  String get createDeliveryYardHelper =>
      'Pick a yard, or leave unselected and enter a custom address below.';

  @override
  String get createDeliveryClearYardAddress => 'Clear yard, use custom address';

  @override
  String get createDeliveryCustomAddress => 'Custom Destination Address';

  @override
  String get createDeliveryContactPhone => 'Contact Phone (optional)';

  @override
  String get createDeliveryDriverTextsHelper => 'The driver texts this number';

  @override
  String get createDeliveryBalanceDue => 'Balance Due';

  @override
  String get createDeliveryAddToBatch => 'Add to Existing Batch (optional)';

  @override
  String get createDeliveryNoBatch => 'No batch';

  @override
  String createDeliveryBatchEntry(String batch, String status) {
    return '$batch ($status)';
  }

  @override
  String get createDeliveryBatchNumber => 'Batch Number';

  @override
  String get createDeliveryBatchNumberRequired => 'Batch number is required';

  @override
  String get createDeliveryScheduledDate => 'Scheduled Date';

  @override
  String get createDeliveryScheduledPickHint => 'Pick a date';

  @override
  String get createDeliveryBatchType => 'Batch Type';

  @override
  String get createDeliveryBatchTypeDealer => 'Dealer';

  @override
  String get createDeliveryBatchTypeBfLocation => 'Bigfoot Location';

  @override
  String get createDeliveryBatchYardHelper =>
      'Pick a yard, or leave unselected and enter a destination name below.';

  @override
  String get createDeliveryClearYardName => 'Clear yard, use custom name';

  @override
  String get createDeliveryDestinationName => 'Destination Name (for dealers)';

  @override
  String createDeliveryTrailersSelected(int n) {
    return 'Trailers  ($n selected)';
  }

  @override
  String get createDeliverySelectTrailer =>
      'Select at least one trailer for the batch.';

  @override
  String get createDeliveryNotReady =>
      'A selected trailer is not ready for delivery';

  @override
  String get createDeliveryNoReadyTrailers =>
      'No ready-for-delivery trailers available.';

  @override
  String createDeliveryStockedAt(String value) {
    return 'Stocked at $value';
  }

  @override
  String createDeliveryCreateFail(String msg) {
    return 'Failed to create: $msg';
  }

  @override
  String get batchScreenDeleteTitle => 'Delete Batch';

  @override
  String batchScreenDeleteBody(String batch, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n delivery records',
      one: '1 delivery record',
    );
    return 'Delete $batch? This removes the batch and its $_temp0. Trailers not yet delivered are returned to the ready-for-delivery pool.';
  }

  @override
  String batchScreenDeleted(String batch) {
    return '$batch deleted.';
  }

  @override
  String batchScreenDeleteFail(String msg) {
    return 'Failed to delete: $msg';
  }

  @override
  String batchScreenCompleteFail(String msg) {
    return 'Failed to complete: $msg';
  }

  @override
  String batchScreenTypeLabel(String value) {
    return 'Type: $value';
  }

  @override
  String batchScreenDriverLabel(String value) {
    return 'Driver: $value';
  }

  @override
  String batchScreenDestinationLabel(String value) {
    return 'Destination: $value';
  }

  @override
  String batchScreenTrailersLabel(int n) {
    return 'Trailers: $n';
  }

  @override
  String batchScreenUpdateTitle(String batch) {
    return 'Update $batch';
  }

  @override
  String get batchScreenDriverField => 'Driver';

  @override
  String get batchScreenCustomDestination => 'Custom destination name';

  @override
  String get batchScreenDestinationName => 'Destination Name';

  @override
  String get batchScreenAddTrailerId => 'Add Trailer ID (optional)';

  @override
  String get batchScreenRemoveDeliveryId => 'Remove Delivery ID (optional)';

  @override
  String batchScreenTrailersInBatchLabel(int count) {
    return 'Currently in batch ($count)';
  }

  @override
  String get batchScreenNoTrailersInBatch => 'No trailers in this batch yet.';

  @override
  String get batchScreenRemoveTrailer => 'Remove from batch';

  @override
  String get batchScreenUndoRemove => 'Undo remove';

  @override
  String batchScreenAddTrailersLabel(int count) {
    return 'Add ready trailers ($count selected)';
  }

  @override
  String batchScreenUpdateFail(String error) {
    return 'Update failed: $error';
  }

  @override
  String get batchScreenCompletedNote =>
      'Batch completed — all trailers delivered.';

  @override
  String get batchScreenUpdate => 'Edit';

  @override
  String get stockInventoryEmptyBody =>
      'No trailers in stock at any yard.\nPull down to refresh.';

  @override
  String get stockInventoryUnknownDate => 'Unknown date';

  @override
  String get stockInventoryDelivered => 'Delivered';

  @override
  String get stockInventoryDeliveredBy => 'Delivered by';

  @override
  String driverDeliveredOn(String date) {
    return 'Delivered $date';
  }
}
