import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/models/qc_inspection.dart';
import '../../../data/models/department.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../viewmodel/qc_viewmodel.dart';
import '../../../shared/widgets/photo_capture_widget.dart';

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

  @override
  void initState() {
    super.initState();
    _loadChecklist();
    _loadUpstreamChecks();
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
        const SnackBar(content: Text('Please answer all checklist items')),
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
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
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
            content: Text('Failed: $e'),
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
    final item = widget.item;
    final totalSteps = _result == 'fail' ? 4 : 3;

    return Scaffold(
      appBar: AppBar(
        title: Text('Inspect ${item.soNumber}'),
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
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Submitting inspection...',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
          : PageView(
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1: Photos',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Photos are optional',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (hasError)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Please wait for pending uploads to finish before continuing',
                style: TextStyle(
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
              title: 'QC Inspection Photos',
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
                    const Text(
                      'Next: Checklist',
                      style: TextStyle(
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
                    const Text(
                      'Step 2: Checklist',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                          ? 'Could not load checklist'
                          : 'No checklist items configured for this department',
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
                      nextLabel: 'Next: Result',
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
              const Text(
                'Step 2: Checklist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                  '$answeredCount of $totalCount',
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
            nextLabel: 'Next: Result',
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
                label: 'PASS',
                isSelected: widget.answer == true,
                color: AppColors.success,
                onTap: widget.onPass,
              ),
              const SizedBox(width: 6),
              // Fail button
              _ToggleButton(
                label: 'FAIL',
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
                  hintText: 'Optional note...',
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
    final passed = upstream.passed;
    final color = passed ? AppColors.success : AppColors.error;
    final who = upstream.checkedByName ?? 'Worker';
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
                  TextSpan(text: '$who$dept marked '),
                  TextSpan(
                    text: passed ? 'PASS' : 'FAIL',
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
                          ? 'Upstream self-checks: $failedCount failed of $totalCount'
                          : 'All $totalCount upstream self-checks passed',
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
                  const Text(
                    'Step 3: Inspection Result',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select the final inspection result',
                    style: TextStyle(color: Colors.grey),
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
                      child: const Row(
                        children: [
                          Icon(Icons.verified, color: AppColors.amber, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'FINAL QC — Passing will mark trailer as Ready for Delivery',
                              style: TextStyle(
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
                          label: 'PASS',
                          icon: Icons.check_circle,
                          color: AppColors.success,
                          isSelected: result == 'pass',
                          onTap: () => onChanged('pass'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ResultCard(
                          label: 'FAIL',
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
                        ? 'Submit Inspection'
                        : 'Next: Fail Details',
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
                  const Text(
                    'Step 4: Fail Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Describe the defect and select rework department',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  // Fail notes (required)
                  TextField(
                    controller: failNotesController,
                    decoration: InputDecoration(
                      labelText: 'Fail Notes *',
                      hintText: 'Describe what failed and needs to be fixed...',
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
                  const Text(
                    'Rework Target Department *',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    DropdownButtonFormField<int>(
                      value: selectedDeptId,
                      decoration: InputDecoration(
                        hintText: 'Select department...',
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
                              'This trailer will be inserted at #1 priority in ${reworkTargets.where((d) => d.id == selectedDeptId).map((d) => d.displayName).firstOrNull ?? "the selected department"}\'s queue',
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
                    nextLabel: 'Submit Inspection',
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
            label: const Text('Back'),
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
        const SnackBar(content: Text('Customer SMS sent')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _smsSending = false);
      messenger.showSnackBar(
        SnackBar(content: Text('SMS failed: ${e.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _smsSending = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('SMS failed — please retry')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        isPassed ? 'QC PASSED' : 'QC FAILED',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isPassed && result.isFinalQc) ...[
                        const Text(
                          'Trailer Ready for Delivery!',
                          style: TextStyle(
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
                              _smsSent ? 'SMS Sent' : 'Send Customer SMS',
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
                              'Next: ${result.nextDepartment}',
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
                                  'Rework sent to ${result.reworkTargetDepartment} at Priority #${result.reworkQueuePosition ?? 1}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 8),
                              const Text(
                                'Production managers have been notified',
                                style: TextStyle(fontSize: 13, color: AppColors.white),
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
                        child: const Text(
                          'Done',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
