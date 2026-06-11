import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/qc_inspection.dart';
import '../../../data/models/department.dart';
import '../../../data/models/trailer.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../../../domain/repositories/trailer_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../viewmodel/qc_viewmodel.dart';
import '../../../shared/widgets/photo_capture_widget.dart';
import '../../../shared/widgets/pdf_viewer_screen.dart';

/// Multi-step QC inspection form: Photos → Checklist → Result → Fail Details → Submit.
class InspectionFormScreen extends StatefulWidget {
  final QcQueueItem item;

  const InspectionFormScreen({super.key, required this.item});

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  final _failNotesController = TextEditingController();
  final _pageController = PageController();

  // Step 1: Photos
  List<String> _photoStorageKeys = [];
  int _photoPendingCount = 0;
  bool _photoError = false;

  // Step 2: Checklist
  List<QcChecklistItem> _checklistItems = [];
  final Map<int, bool?> _checklistAnswers = {}; // itemId -> pass/fail
  final Map<int, TextEditingController> _checklistNotes = {};
  bool _checklistLoading = true;
  // Captures whatever broke the fetch/parse so the empty-state can show
  // a real reason ("auth expired", "could not parse field X", …) instead
  // of the generic "No checklist items configured for this department".
  String? _checklistError;

  // Upstream self-check results from production workers (read-only)
  List<UpstreamCheck> _upstreamChecks = const [];
  // QC item id -> the matching upstream worker check (paired by label).
  // Drives pre-fill of answers/notes and inline display in each checklist row.
  Map<int, UpstreamCheck> _upstreamByItemId = const {};

  // Step 3: Result
  String _result = 'pass';

  // Step 4: Fail details
  List<Department> _reworkTargets = [];
  int? _selectedReworkDeptId;
  bool _reworkTargetsLoading = false;

  // Submission
  bool _isSubmitting = false;
  int _currentPage = 0;

  // Trailer summary pinned above the inspection form. Loaded once on open
  // so the inspector has model / customer / size / options visible before
  // they take a single photo, and can pull the QB SO PDF without going
  // back to the queue.
  Trailer? _trailerDetail;

  @override
  void initState() {
    super.initState();
    _loadChecklist();
    _loadUpstreamChecks();
    _loadTrailerDetail();
  }

  Future<void> _loadTrailerDetail() async {
    try {
      final trailer = await context
          .read<TrailerRepository>()
          .getTrailer(widget.item.trailerId);
      if (!mounted) return;
      setState(() => _trailerDetail = trailer);
    } catch (_) {
      // Non-fatal — the banner just falls back to the limited QC queue info.
    }
  }

  Future<void> _loadUpstreamChecks() async {
    try {
      final checks = await context.read<QcViewModel>().fetchUpstreamChecks(
        widget.item.trailerId,
      );
      if (!mounted) return;
      setState(() => _upstreamChecks = checks);
      _mergeUpstreamIntoChecklist();
    } catch (_) {
      // Non-fatal — the inline upstream context just stays empty.
    }
  }

  /// After both the QC checklist items and the upstream worker self-checks
  /// have loaded, pair them by item_label and:
  ///   1. Pre-fill the inspector's PASS/FAIL toggle from the worker's answer
  ///      (the inspector reviews/overrides instead of redoing 22 toggles).
  ///   2. Copy the worker's note into the inspector's note field as a
  ///      starting point — the inspector can edit or replace it.
  /// Idempotent: only fills empty answers/notes, so re-running won't clobber
  /// edits the inspector has already made.
  void _mergeUpstreamIntoChecklist() {
    if (_checklistItems.isEmpty || _upstreamChecks.isEmpty) return;
    final byLabel = <String, UpstreamCheck>{};
    for (final c in _upstreamChecks) {
      byLabel[c.itemLabel] = c;
    }
    final mapped = <int, UpstreamCheck>{};
    for (final item in _checklistItems) {
      final upstream = byLabel[item.label];
      if (upstream == null) continue;
      mapped[item.id] = upstream;
      _checklistAnswers[item.id] ??= upstream.passed;
      final ctrl = _checklistNotes[item.id];
      if (ctrl != null &&
          ctrl.text.isEmpty &&
          upstream.note != null &&
          upstream.note!.isNotEmpty) {
        ctrl.text = upstream.note!;
      }
    }
    setState(() => _upstreamByItemId = mapped);
  }

  @override
  void dispose() {
    _failNotesController.dispose();
    _pageController.dispose();
    for (final c in _checklistNotes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadChecklist() async {
    try {
      final items = await context.read<QcViewModel>().fetchChecklistItems(
        departmentId: widget.item.departmentId,
        series: widget.item.series,
        trailerId: widget.item.trailerId,
      );
      if (!mounted) return;
      setState(() {
        _checklistItems = items;
        _checklistLoading = false;
        _checklistError = null;
        for (final item in items) {
          _checklistNotes[item.id] = TextEditingController();
        }
      });
      _mergeUpstreamIntoChecklist();
    } on ApiException catch (e) {
      debugPrint(
        'QC checklist load failed (api): code=${e.code} msg=${e.displayMessage}',
      );
      if (mounted) {
        setState(() {
          _checklistLoading = false;
          _checklistError = '${e.code}: ${e.displayMessage}';
        });
      }
    } catch (e, stack) {
      debugPrint('QC checklist load failed (other): $e\n$stack');
      if (mounted) {
        setState(() {
          _checklistLoading = false;
          _checklistError = e.toString();
        });
      }
    }
  }

  Future<void> _loadReworkTargets() async {
    if (_reworkTargets.isNotEmpty) return;
    setState(() => _reworkTargetsLoading = true);
    try {
      final targets = await context.read<QcViewModel>().fetchReworkTargets(
        widget.item.trailerId,
      );
      if (mounted) {
        setState(() {
          _reworkTargets = targets;
          _reworkTargetsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _reworkTargetsLoading = false);
    }
  }

  void _goToPage(int page) {
    // Validation before advancing
    if (page > 1 && _currentPage == 1 && !_allChecklistAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).qcAnswerAll)),
      );
      return;
    }
    if (page == 3 && _result == 'fail') {
      _loadReworkTargets();
    }
    // Skip fail details page if result is pass
    if (page == 3 && _result == 'pass') {
      _submit();
      return;
    }
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage = page);
  }

  bool get _allChecklistAnswered =>
      _checklistItems.every((item) => _checklistAnswers[item.id] != null);

  int get _answeredCount =>
      _checklistAnswers.values.where((v) => v != null).length;

  bool get _canSubmit {
    if (_photoPendingCount > 0) return false;
    if (!_allChecklistAnswered) return false;
    if (_result == 'fail') {
      if (_failNotesController.text.trim().isEmpty) return false;
      if (_selectedReworkDeptId == null) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.qcFillRequired)),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final navigator = Navigator.of(context);
      final cubit = context.read<QcViewModel>();

      // Build checklist results
      final checklistResults = _checklistItems.map((item) {
        return {
          'checklistItemId': item.id,
          'passed': _checklistAnswers[item.id] ?? true,
          if (_checklistNotes[item.id]?.text.trim().isNotEmpty == true)
            'note': _checklistNotes[item.id]!.text.trim(),
        };
      }).toList();

      // Submit
      final result = await cubit.submitInspection(
        productionStepId: widget.item.stepId,
        result: _result,
        failNotes: _result == 'fail' ? _failNotesController.text.trim() : null,
        reworkTargetDepartmentId: _result == 'fail'
            ? _selectedReworkDeptId
            : null,
        checklistResults: checklistResults,
        photoStorageKeys: _photoStorageKeys,
      );

      if (!mounted) return;
      // Show result screen
      navigator.pop();
      _showResultScreen(navigator.context, result);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.displayMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.commonFailed('$e')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showResultScreen(BuildContext ctx, QcInspectionResult result) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _InspectionResultDialog(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.item;
    final totalSteps = _result == 'fail' ? 4 : 3;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.qcInspectTitle(item.soNumber)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentPage + 1) / totalSteps,
            backgroundColor: Colors.grey.shade200,
            color: AppColors.amber,
          ),
        ),
      ),
      body: _isSubmitting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    l.qcSubmittingInspection,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
          : Column(children: [
              // Trailer info banner — collapsed to one line by default, opens
              // to show the full spec sheet. The "Open SO PDF" button uses
              // the existing PDF viewer route and is hidden when the trailer
              // has no QB PDF attached yet.
              _TrailerInfoBanner(
                item: widget.item,
                trailer: _trailerDetail,
              ),
              Expanded(child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: [
                _PhotosStep(
                  trailerId: widget.item.trailerId,
                  hasError: _photoError,
                  onChanged: (snapshot) {
                    setState(() {
                      _photoStorageKeys = snapshot.storageKeys;
                      _photoPendingCount = snapshot.pendingCount;
                      _photoError = snapshot.pendingCount > 0;
                    });
                  },
                  onNext: () => _goToPage(1),
                ),
                _ChecklistStep(
                  items: _checklistItems,
                  answers: _checklistAnswers,
                  notes: _checklistNotes,
                  isLoading: _checklistLoading,
                  loadError: _checklistError,
                  answeredCount: _answeredCount,
                  totalCount: _checklistItems.length,
                  upstreamChecks: _upstreamChecks,
                  upstreamByItemId: _upstreamByItemId,
                  onAnswer: (id, val) =>
                      setState(() => _checklistAnswers[id] = val),
                  onBack: () => _goToPage(0),
                  onNext: () {
                    // Auto-determine result based on checklist
                    final anyFailed = _checklistAnswers.values.any(
                      (v) => v == false,
                    );
                    setState(() => _result = anyFailed ? 'fail' : 'pass');
                    _goToPage(2);
                  },
                ),
                _ResultStep(
                  result: _result,
                  onChanged: (v) => setState(() => _result = v),
                  onBack: () => _goToPage(1),
                  onNext: () => _goToPage(3),
                  isFinalQc: item.departmentCode == 'FINAL_QC',
                ),
                _FailDetailsStep(
                  failNotesController: _failNotesController,
                  reworkTargets: _reworkTargets,
                  selectedDeptId: _selectedReworkDeptId,
                  isLoading: _reworkTargetsLoading,
                  onDeptSelected: (id) =>
                      setState(() => _selectedReworkDeptId = id),
                  onBack: () => _goToPage(2),
                  onSubmit: _canSubmit ? _submit : null,
                ),
              ],
            )),
            ]),
    );
  }
}

/// One-line trailer summary that expands to the full spec + an "Open SO
/// PDF" action. Pinned above the inspection PageView so the inspector
/// always has the trailer's basics in view.
class _TrailerInfoBanner extends StatelessWidget {
  final QcQueueItem item;
  final Trailer? trailer;

  const _TrailerInfoBanner({required this.item, required this.trailer});

  String? get _model => trailer?.trailerModel?.displayName ?? item.modelName;
  String? get _customer =>
      trailer?.customer?.name ?? trailer?.soldToName ?? item.customerName;
  String? get _size => trailer?.size;
  String? get _color => trailer?.color;
  String? get _options => trailer?.optionsNotes;
  String? get _specialNote => trailer?.specialNote;
  String? get _saleStatus => trailer?.saleStatus;
  String? get _qbPdfKey => trailer?.qbSoPdfStorageKey;

  void _openPdf(BuildContext context) {
    final key = _qbPdfKey;
    if (key == null || key.isEmpty) return;
    context.pushNamed(
      RouteNames.pdfViewer,
      extra: PdfViewerArgs(storageKey: key, title: item.soNumber),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasPdf = _qbPdfKey != null && _qbPdfKey!.isNotEmpty;
    final summary = [_model, _customer]
        .where((s) => s != null && s.isNotEmpty)
        .join(' • ');

    return Material(
      color: AppColors.navy.withValues(alpha: 0.04),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        childrenPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: const Icon(Icons.local_shipping_outlined,
            color: AppColors.navy, size: 22),
        title: Row(
          children: [
            Text(
              item.soNumber,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        trailing: hasPdf
            ? IconButton(
                tooltip: l.trailerDetailOpenPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined,
                    color: AppColors.navy),
                onPressed: () => _openPdf(context),
              )
            : null,
        children: [
          if (trailer == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else ...[
            _kv(l.qcInfoModel, _model),
            _kv(l.qcInfoSize, _size),
            _kv(l.qcInfoColor, _color),
            _kv(l.qcInfoCustomer, _customer),
            _kv(l.qcInfoSaleStatus, _saleStatus),
            _kv(l.qcInfoOptions, _options, multiline: true),
            _kv(l.qcInfoSpecialNote, _specialNote, multiline: true),
            if (hasPdf)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openPdf(context),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(l.trailerDetailOpenPdf),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String label, String? value, {bool multiline = false}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: multiline ? 4 : 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 1: Photos ───────────────────────────────────────────────────────────

class _PhotosStep extends StatelessWidget {
  final int trailerId;
  final bool hasError;
  final ValueChanged<PhotoCaptureSnapshot> onChanged;
  final VoidCallback onNext;

  const _PhotosStep({
    required this.trailerId,
    required this.hasError,
    required this.onChanged,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.qcStep1Title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            l.qcStep1Subtitle,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l.qcStep1PendingUploads,
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 16),
          const SizedBox(height: 8),
          Expanded(
            child: PhotoCaptureWidget(
              fileType: 'qc_photo',
              title: l.qcInspectionPhotos,
              trailerId: trailerId,
              minPhotoCount: 0,
              onChanged: onChanged,
            ),
          ),
          // Next button
          const SizedBox(height: 12),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: onNext,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l.qcNextChecklist,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 2: Checklist ────────────────────────────────────────────────────────

class _ChecklistStep extends StatelessWidget {
  final List<QcChecklistItem> items;
  final Map<int, bool?> answers;
  final Map<int, TextEditingController> notes;
  final bool isLoading;
  // Real reason the checklist fetch/parse failed, or null if it succeeded.
  // Surfaced in the empty-state UI so we don't mistake "auth failed" or
  // "JSON parse error" for "this department has no items configured".
  final String? loadError;
  final int answeredCount;
  final int totalCount;
  final List<UpstreamCheck> upstreamChecks;
  final Map<int, UpstreamCheck> upstreamByItemId;
  final void Function(int id, bool passed) onAnswer;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _ChecklistStep({
    required this.items,
    required this.answers,
    required this.notes,
    required this.isLoading,
    required this.loadError,
    required this.answeredCount,
    required this.totalCount,
    required this.upstreamChecks,
    required this.upstreamByItemId,
    required this.onAnswer,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final l = AppLocalizations.of(context);
    if (items.isEmpty) {
      final hasError = loadError != null;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Text(
                      l.qcStep2Title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 24),
                    Icon(
                      hasError ? Icons.error_outline : Icons.info_outline,
                      size: 48,
                      color: hasError ? AppColors.error : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasError
                          ? l.qcChecklistLoadFail
                          : l.qcChecklistNotConfigured,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (hasError) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          loadError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                    const Spacer(),
                    _NavButtons(
                      onBack: onBack,
                      onNext: onNext,
                      nextLabel: l.qcNextResult,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.qcStep2Title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: answeredCount == totalCount
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l.qcAnsweredOf(answeredCount, totalCount),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: answeredCount == totalCount
                        ? AppColors.success
                        : AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                if (upstreamChecks.isNotEmpty)
                  _UpstreamChecksPanel(checks: upstreamChecks),
                ...List.generate(items.length * 2 - (items.isEmpty ? 0 : 1), (
                  i,
                ) {
                  if (i.isOdd) return const Divider(height: 1);
                  final item = items[i ~/ 2];
                  final answer = answers[item.id];
                  return _ChecklistRow(
                    item: item,
                    answer: answer,
                    noteController: notes[item.id]!,
                    upstream: upstreamByItemId[item.id],
                    onPass: () => onAnswer(item.id, true),
                    onFail: () => onAnswer(item.id, false),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _NavButtons(
            onBack: onBack,
            onNext: answeredCount == totalCount ? onNext : null,
            nextLabel: l.qcNextResult,
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatefulWidget {
  final QcChecklistItem item;
  final bool? answer;
  final TextEditingController noteController;
  // The matching worker self-check from the upstream production department,
  // null when no upstream answer was found for this item.
  final UpstreamCheck? upstream;
  final VoidCallback onPass;
  final VoidCallback onFail;

  const _ChecklistRow({
    required this.item,
    required this.answer,
    required this.noteController,
    required this.upstream,
    required this.onPass,
    required this.onFail,
  });

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late bool _showNote;

  @override
  void initState() {
    super.initState();
    // Auto-expand the note field when the upstream worker left a note OR
    // when the upstream worker failed the item — both cases are things the
    // QC manager almost always wants to see/edit.
    final u = widget.upstream;
    _showNote = (u?.note?.isNotEmpty ?? false) || (u != null && !u.passed);
  }

  @override
  Widget build(BuildContext context) {
    final upstream = widget.upstream;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.item.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Pass button
              _ToggleButton(
                label: AppLocalizations.of(context).qcPass,
                isSelected: widget.answer == true,
                color: AppColors.success,
                onTap: widget.onPass,
              ),
              const SizedBox(width: 6),
              // Fail button
              _ToggleButton(
                label: AppLocalizations.of(context).qcFail,
                isSelected: widget.answer == false,
                color: AppColors.error,
                onTap: widget.onFail,
              ),
              const SizedBox(width: 6),
              // Note toggle
              GestureDetector(
                onTap: () => setState(() => _showNote = !_showNote),
                child: Icon(
                  _showNote ? Icons.note : Icons.note_add_outlined,
                  size: 20,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          if (upstream != null) _UpstreamHint(upstream: upstream),
          if (_showNote)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: widget.noteController,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).qcOptionalNote,
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact "Worker [name] marked PASS/FAIL — [note]" badge shown below
/// each checklist row when the matching upstream self-check exists.
class _UpstreamHint extends StatelessWidget {
  final UpstreamCheck upstream;
  const _UpstreamHint({required this.upstream});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final passed = upstream.passed;
    final color = passed ? AppColors.success : AppColors.error;
    final who = upstream.checkedByName ?? l.qcWorker;
    final dept = upstream.departmentCode.isNotEmpty
        ? ' (${upstream.departmentCode})'
        : '';
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                children: [
                  TextSpan(text: l.qcUpstreamMarkedPrefix(who, dept)),
                  TextSpan(
                    text: passed ? l.qcPass : l.qcFail,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  if (upstream.note != null && upstream.note!.isNotEmpty)
                    TextSpan(
                      text: ' — "${upstream.note}"',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

// ── Upstream Worker Self-Checks Panel (read-only) ────────────────────────────

class _UpstreamChecksPanel extends StatefulWidget {
  final List<UpstreamCheck> checks;
  const _UpstreamChecksPanel({required this.checks});

  @override
  State<_UpstreamChecksPanel> createState() => _UpstreamChecksPanelState();
}

class _UpstreamChecksPanelState extends State<_UpstreamChecksPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Group by department code
    final byDept = <String, List<UpstreamCheck>>{};
    for (final c in widget.checks) {
      byDept.putIfAbsent(c.departmentCode, () => []).add(c);
    }
    final failedCount = widget.checks.where((c) => !c.passed).length;
    final totalCount = widget.checks.length;
    final hasFailures = failedCount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: hasFailures
            ? AppColors.warning.withValues(alpha: 0.06)
            : AppColors.success.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasFailures
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    hasFailures ? Icons.warning_amber : Icons.verified_outlined,
                    color: hasFailures ? AppColors.warning : AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasFailures
                          ? AppLocalizations.of(context)
                              .qcUpstreamFailedCount(failedCount, totalCount)
                          : AppLocalizations.of(context)
                              .qcUpstreamAllPassed(totalCount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in byDept.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        entry.value.first.departmentName.isNotEmpty
                            ? '${entry.key} · ${entry.value.first.departmentName}'
                            : entry.key,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    ...entry.value.map((c) => _UpstreamCheckRow(check: c)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UpstreamCheckRow extends StatelessWidget {
  final UpstreamCheck check;
  const _UpstreamCheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            check.passed ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: check.passed ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.itemLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (check.note != null && check.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${check.note}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (check.checkedByName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '— ${check.checkedByName}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 3: Result ───────────────────────────────────────────────────────────

class _ResultStep extends StatelessWidget {
  final String result;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final bool isFinalQc;

  const _ResultStep({
    required this.result,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
    required this.isFinalQc,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.qcStep3Title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.qcStep3Subtitle,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  if (isFinalQc)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.amber),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified, color: AppColors.amber, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.qcFinalQcWarning,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 32),
                  // Pass / Fail toggle
                  Row(
                    children: [
                      Expanded(
                        child: _ResultCard(
                          label: l.qcPass,
                          icon: Icons.check_circle,
                          color: AppColors.success,
                          isSelected: result == 'pass',
                          onTap: () => onChanged('pass'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ResultCard(
                          label: l.qcFail,
                          icon: Icons.cancel,
                          color: AppColors.error,
                          isSelected: result == 'fail',
                          onTap: () => onChanged('fail'),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _NavButtons(
                    onBack: onBack,
                    onNext: onNext,
                    nextLabel: result == 'pass'
                        ? l.qcSubmitInspection
                        : l.qcNextFailDetails,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ResultCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 140,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: isSelected ? color : Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isSelected ? color : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 4: Fail Details ─────────────────────────────────────────────────────

class _FailDetailsStep extends StatelessWidget {
  final TextEditingController failNotesController;
  final List<Department> reworkTargets;
  final int? selectedDeptId;
  final bool isLoading;
  final ValueChanged<int> onDeptSelected;
  final VoidCallback onBack;
  final VoidCallback? onSubmit;

  const _FailDetailsStep({
    required this.failNotesController,
    required this.reworkTargets,
    required this.selectedDeptId,
    required this.isLoading,
    required this.onDeptSelected,
    required this.onBack,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.qcStep4Title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.qcStep4Subtitle,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  // Fail notes (required)
                  TextField(
                    controller: failNotesController,
                    decoration: InputDecoration(
                      labelText: l.qcFailNotesLabel,
                      hintText: l.qcFailNotesHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                      errorText: failNotesController.text.isEmpty ? null : null,
                    ),
                    maxLines: 4,
                    onChanged: (_) => (context as Element).markNeedsBuild(),
                  ),
                  const SizedBox(height: 16),
                  // Rework target department
                  Text(
                    l.qcReworkTargetLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<int>(
                      value: selectedDeptId,
                      decoration: InputDecoration(
                        hintText: l.qcSelectDept,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      items: reworkTargets.map((d) {
                        return DropdownMenuItem(
                          value: d.id,
                          child: Text(
                            '${d.displayName} (${d.code})',
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: (id) {
                        if (id != null) onDeptSelected(id);
                      },
                    ),
                  // Warning banner
                  if (selectedDeptId != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            color: AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.qcInsertedAtPriorityOne(reworkTargets
                                      .where((d) => d.id == selectedDeptId)
                                      .map((d) => d.displayName)
                                      .firstOrNull ??
                                  l.qcTheSelectedDept),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  _NavButtons(
                    onBack: onBack,
                    onNext: onSubmit,
                    nextLabel: l.qcSubmitInspection,
                    nextColor: AppColors.error,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Navigation Buttons ───────────────────────────────────────────────────────

class _NavButtons extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onNext;
  final String nextLabel;
  final Color? nextColor;

  const _NavButtons({
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
    this.nextColor,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(AppLocalizations.of(context).commonBack),
          ),
          const Spacer(),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: onNext,
              style: nextColor != null
                  ? FilledButton.styleFrom(backgroundColor: nextColor)
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nextLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inspection Result Dialog ─────────────────────────────────────────────────

class _InspectionResultDialog extends StatefulWidget {
  final QcInspectionResult result;
  const _InspectionResultDialog({required this.result});

  @override
  State<_InspectionResultDialog> createState() =>
      _InspectionResultDialogState();
}

class _InspectionResultDialogState extends State<_InspectionResultDialog> {
  bool _smsSending = false;
  bool _smsSent = false;

  Future<void> _sendSms() async {
    if (_smsSending || _smsSent) return;
    setState(() => _smsSending = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<QcRepository>().sendCustomerSms(
        widget.result.inspectionId,
      );
      if (!mounted) return;
      setState(() {
        _smsSending = false;
        _smsSent = true;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).qcCustomerSmsSent)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _smsSending = false);
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).qcSmsFailed(e.message))),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _smsSending = false);
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).qcSmsFailedRetry)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final result = widget.result;
    final isPassed = result.isPassed;
    final bgColor = isPassed ? AppColors.success : AppColors.error;

    return Dialog.fullscreen(
      backgroundColor: bgColor,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPassed ? Icons.check_circle : Icons.cancel,
                        size: 96,
                        color: AppColors.white,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isPassed ? l.qcResultPassed : l.qcResultFailed,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isPassed && result.isFinalQc) ...[
                        Text(
                          l.qcReadyForDelivery,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        if (result.smsReady) ...[
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _smsSent || _smsSending ? null : _sendSms,
                            icon: _smsSending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.white,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    _smsSent ? Icons.check : Icons.sms,
                                    color: AppColors.white,
                                  ),
                            label: Text(
                              _smsSent ? l.qcSmsSent : l.qcSendSms,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.white),
                              minimumSize: const Size(200, 48),
                            ),
                          ),
                        ],
                      ] else if (isPassed) ...[
                        if (result.nextDepartment != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              l.queueOverlayNext(result.nextDepartment!),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                      ] else ...[
                        // Fail info
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              if (result.reworkTargetDepartment != null)
                                Text(
                                  l.qcReworkSentTo(
                                      result.reworkTargetDepartment!,
                                      result.reworkQueuePosition ?? 1),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 8),
                              Text(
                                l.qcManagersNotified,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.white,
                          foregroundColor: bgColor,
                          minimumSize: const Size(160, 48),
                        ),
                        child: Text(
                          l.commonDone,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
