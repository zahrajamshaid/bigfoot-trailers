import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/queue_item.dart';
import '../../../domain/repositories/production_repository.dart';
import '../viewmodel/production_viewmodel.dart';
import '../../../shared/widgets/pdf_viewer_screen.dart';
import '../../../shared/widgets/status_badge.dart';

/// Full-screen confirmation dialog for completing a production step.
/// Shows trailer details, optional notes, and a big "Complete Step" button.
class StepCompletionDialog extends StatefulWidget {
  final QueueItem item;

  const StepCompletionDialog({super.key, required this.item});

  @override
  State<StepCompletionDialog> createState() => _StepCompletionDialogState();
}

class _StepCompletionDialogState extends State<StepCompletionDialog>
    with SingleTickerProviderStateMixin {
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  bool _showSuccess = false;
  StepCompletionResult? _result;
  late final AnimationController _successAnimCtrl;
  late final Animation<double> _successScale;

  // Checklist state
  bool _loadingChecklist = true;
  String? _checklistError;
  List<StepChecklistItem> _checklistItems = const [];
  // itemId -> passed?; null = unanswered
  final Map<int, bool?> _answers = {};
  // itemId -> note controller (lazy)
  final Map<int, TextEditingController> _noteControllers = {};

  @override
  void initState() {
    super.initState();
    _successAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _successScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _successAnimCtrl, curve: Curves.elasticOut),
    );
    _loadChecklist();
  }

  Future<void> _loadChecklist() async {
    try {
      final items = await context
          .read<ProductionViewModel>()
          .loadStepChecklist(widget.item.stepId);
      if (!mounted) return;
      setState(() {
        _checklistItems = items;
        for (final i in items) {
          _answers[i.id] = null;
        }
        _loadingChecklist = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _checklistError = e.displayMessage;
        _loadingChecklist = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checklistError = 'Failed to load checklist: $e';
        _loadingChecklist = false;
      });
    }
  }

  TextEditingController _noteController(int itemId) =>
      _noteControllers.putIfAbsent(itemId, () => TextEditingController());

  bool get _checklistComplete {
    if (_checklistItems.isEmpty) return true;
    for (final item in _checklistItems) {
      final a = _answers[item.id];
      if (a == null) return false;
      if (a == false) {
        final note = _noteControllers[item.id]?.text.trim() ?? '';
        if (note.isEmpty) return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    _successAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_checklistComplete) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Answer every checklist item. Notes are required on any "No".'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final results = _checklistItems
        .map((i) => StepCheckResult(
              checklistItemId: i.id,
              passed: _answers[i.id] == true,
              note: _noteControllers[i.id]?.text.trim().isEmpty ?? true
                  ? null
                  : _noteControllers[i.id]!.text.trim(),
            ))
        .toList();

    try {
      final result = await context.read<ProductionViewModel>().completeStep(
            widget.item.stepId,
            notes: _notesController.text.trim(),
            checklistResults: results.isEmpty ? null : results,
          );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _showSuccess = true;
        _result = result;
      });
      _successAnimCtrl.forward();
      HapticFeedback.heavyImpact();

      // Auto-close after 2 seconds
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.displayMessage),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    if (_showSuccess) {
      return Dialog.fullscreen(
        backgroundColor: AppColors.success,
        child: _SuccessView(
          result: _result,
          scaleAnimation: _successScale,
          onClose: () => Navigator.pop(context),
        ),
      );
    }

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complete Step'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SO Number header
              Center(
                child: Text(
                  item.soNumber,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Badges row
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.series != null) ...[
                      SeriesBadge(series: item.series!),
                      const SizedBox(width: 8),
                    ],
                    if (item.isHot)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('🔥', style: TextStyle(fontSize: 12)),
                            SizedBox(width: 4),
                            Text('HOT',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Detail card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.modelName != null)
                        _DetailRow(label: 'Model', value: item.modelName!),
                      if (item.customerName != null && item.customerName!.isNotEmpty)
                        _DetailRow(label: 'Customer', value: item.customerName!),
                      if (item.color != null)
                        _DetailRow(label: 'Color', value: item.color!),
                      if (item.size != null)
                        _DetailRow(label: 'Size', value: '${item.size}ft'),
                      if (item.optionsNotes != null && item.optionsNotes!.isNotEmpty)
                        _DetailRow(label: 'Notes', value: item.optionsNotes!),
                      if (item.qbSoPdfStorageKey != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.pushNamed(
                                  RouteNames.pdfViewer,
                                  extra: PdfViewerArgs(
                                    storageKey: item.qbSoPdfStorageKey!,
                                    title: '${item.soNumber} — QB Sales Order',
                                  ),
                                ),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('View QB Sales Order'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/trailers/${item.trailerId}'),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Full Details'),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/trailers/${item.trailerId}'),
                          icon: const Icon(Icons.info_outline),
                          label: const Text('View full trailer details'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Rework fail notes (prominent red box)
              if (item.isRework && item.reworkFailNotes != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'REWORK — QC Fail Notes (×${item.reworkCount})',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.error,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.reworkFailNotes!,
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],

              // Rework badge (no points warning)
              if (item.isRework) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Rework steps award 0 points.',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Self-check list ────────────────────────────────────────
              const SizedBox(height: 20),
              if (_loadingChecklist)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_checklistError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_checklistError!)),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _loadingChecklist = true;
                            _checklistError = null;
                          });
                          _loadChecklist();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else if (_checklistItems.isNotEmpty) ...[
                const Text(
                  'Self-Check',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Confirm each item before completing. Notes are required on any "No".',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                ...List.generate(_checklistItems.length, (idx) {
                  final item = _checklistItems[idx];
                  return _ChecklistRow(
                    item: item,
                    answer: _answers[item.id],
                    noteController: _noteController(item.id),
                    onChanged: (v) => setState(() => _answers[item.id] = v),
                    onNoteChanged: () => setState(() {}),
                  );
                }),
              ],

              // Optional notes field
              const SizedBox(height: 20),
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Completion Notes (optional)',
                  hintText: 'Any notes about this step...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(16),
                ),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 32),

              // Complete button — large for glove use
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton.icon(
                  onPressed: (_isSubmitting || _loadingChecklist || !_checklistComplete)
                      ? null
                      : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle, size: 28),
                  label: Text(
                    _isSubmitting ? 'Completing...' : 'COMPLETE STEP',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final StepChecklistItem item;
  final bool? answer;
  final TextEditingController noteController;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onNoteChanged;

  const _ChecklistRow({
    required this.item,
    required this.answer,
    required this.noteController,
    required this.onChanged,
    required this.onNoteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final failedWithoutNote = answer == false && noteController.text.trim().isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: failedWithoutNote
              ? AppColors.error.withValues(alpha: 0.5)
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _AnswerButton(
                  label: 'Yes',
                  icon: Icons.check,
                  selected: answer == true,
                  selectedColor: AppColors.success,
                  onTap: () => onChanged(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AnswerButton(
                  label: 'No',
                  icon: Icons.close,
                  selected: answer == false,
                  selectedColor: AppColors.error,
                  onTap: () => onChanged(false),
                ),
              ),
            ],
          ),
          if (answer == false) ...[
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              onChanged: (_) => onNoteChanged(),
              decoration: InputDecoration(
                hintText: 'Note (required)',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? selectedColor : Colors.grey.shade400,
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.white : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.white : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final StepCompletionResult? result;
  final Animation<double> scaleAnimation;
  final VoidCallback onClose;

  const _SuccessView({
    required this.result,
    required this.scaleAnimation,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated checkmark
          ScaleTransition(
            scale: scaleAnimation,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 80,
                color: AppColors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Step Complete!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 16),
            Text(
              result!.pointsAwarded > 0
                  ? '+${result!.pointsAwarded.toStringAsFixed(1)} points'
                  : 'Rework — 0 points',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
              ),
            ),
            if (result!.nextDepartment != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Next → ${result!.nextDepartment}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 40),
          TextButton(
            onPressed: onClose,
            child: const Text(
              'Close',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
