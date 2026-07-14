import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/router/route_names.dart';
import '../data/trailer_options_api.dart';

/// Production-manager / admin box: options added AFTER the build started.
///
/// Drew: "right now if someone adds D-rings while it is past weld in production
/// no one knows, it never gets them, and no one notices till after the trailer
/// is built — then it has to be rebuilt."
///
/// Each card shows the trailer's whole production line as a strip: where the
/// build is now, and which stages still owe this option. A stage the build has
/// already passed that still owes the option is the danger case — that worker
/// will never see it. Tap any stage to move the build there (back OR forward).
///
/// "Reviewed" clears the card off this dashboard only. It does NOT fit the
/// option — the assigned departments still have to acknowledge it at their own
/// step, and that gate stays in force.
class OptionsReviewScreen extends StatefulWidget {
  const OptionsReviewScreen({super.key});

  @override
  State<OptionsReviewScreen> createState() => _OptionsReviewScreenState();
}

class _OptionsReviewScreenState extends State<OptionsReviewScreen> {
  late final TrailerOptionsApi _api;
  bool _loading = true;
  int? _busyId;
  List<PendingOptionReview> _rows = const [];

  @override
  void initState() {
    super.initState();
    _api = TrailerOptionsApi(context.read<DioClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _api.pendingReview();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rows = const []);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _dangerCount => _rows.where((r) => r.needsRollback).length;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _markReviewed(PendingOptionReview r) async {
    setState(() => _busyId = r.id);
    try {
      await _api.review(r.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.outstandingDepartments.isEmpty
              ? 'Reviewed — cleared from the dashboard'
              : 'Reviewed. ${r.outstandingDepartments.join(', ')} must still '
                  'acknowledge fitting it.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// The department's readable name ("XP Jig"), falling back to its code.
  /// Step ids are an internal detail — the UI always names the department.
  String _deptLabel(PendingOptionReview r, String code) {
    final s = r.steps.where((x) => x.code == code).firstOrNull;
    final name = s?.name.trim() ?? '';
    return name.isEmpty ? code : name;
  }

  /// Move the build to a stage — earlier sends it back, later moves it forward.
  Future<void> _moveTo(PendingOptionReview r, OptionStep s) async {
    if (s.isCurrent) return;
    final back = !s.isAfterCurrent(r);
    final dept = s.name.trim().isEmpty ? s.code : s.name;
    final now = r.currentDepartment == null
        ? '—'
        : _deptLabel(r, r.currentDepartment!);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(back
            ? 'Send SO ${r.soNumber} back to $dept?'
            : 'Move SO ${r.soNumber} forward to $dept?'),
        content: Text(
          back
              ? '$dept still has to fit "${r.option}", but the build has already '
                  'gone past it (now at $now).\n\n'
                  'It will never see this option unless you send the trailer back.'
              : 'This moves the build forward to $dept. Stages in between are '
                  'marked complete.\n\n'
                  'Only do this if "${r.option}" does not need them.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: back ? AppColors.warning : AppColors.navy,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(back ? 'Send back' : 'Move forward'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyId = r.id);
    try {
      await _api.moveToStep(
        trailerId: r.trailerId,
        stepId: s.stepId,
        reason: 'Option "${r.option}" — sent to $dept',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SO ${r.soNumber} sent to $dept')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Move failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Options Added Mid-Build'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _rows.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      _summary(),
                      const SizedBox(height: 12),
                      for (final r in _rows) ...[
                        _card(r),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_outlined,
                  size: 64, color: AppColors.success),
              const SizedBox(height: 16),
              const Text('Nothing to review',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'No options have been added to a trailer since its build started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.disabled, fontSize: 13),
              ),
            ],
          ),
        ),
      );

  /// Headline: how many trailers are on course to be built wrong.
  Widget _summary() {
    final danger = _dangerCount;
    final total = _rows.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger > 0
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: danger > 0
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            danger > 0 ? Icons.error_outline : Icons.info_outline,
            color: danger > 0 ? AppColors.error : AppColors.navy,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  danger > 0
                      ? '$danger of $total will be built wrong'
                      : '$total option${total == 1 ? '' : 's'} to review',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: danger > 0 ? AppColors.error : AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  danger > 0
                      ? 'The build has already passed a department that still has '
                          'to fit the option. Send it back, or it gets finished wrong.'
                      : 'Options added after these builds started.',
                  style: const TextStyle(fontSize: 12, color: AppColors.disabled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(PendingOptionReview r) {
    final busy = _busyId == r.id;
    final danger = r.needsRollback;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: danger ? AppColors.error : AppColors.divider,
          width: danger ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: SO + danger flag ──────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: danger
                  ? AppColors.error.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => context.pushNamed(
                      RouteNames.trailerDetail,
                      pathParameters: {'id': '${r.trailerId}'},
                    ),
                    child: Row(
                      children: [
                        Text('SO ${r.soNumber}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: AppColors.navy)),
                        const SizedBox(width: 8),
                        Text(r.model,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.disabled)),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new,
                            size: 13, color: AppColors.disabled),
                      ],
                    ),
                  ),
                ),
                if (danger)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('WILL BE BUILT WRONG',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.3)),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── The option ────────────────────────────────────────
                Text(r.option,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (r.notes?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(r.notes!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.disabled)),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Added by ${r.addedBy}'
                  '${r.addedPastDepartment != null ? ' · past ${r.addedPastDepartment}' : ''}',
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.disabled),
                ),

                const SizedBox(height: 14),

                // ── Who has to fit it ─────────────────────────────────
                const Text('WHO FITS IT',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.disabled)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: r.fittedBy.map((f) {
                    final missed = r.missedDepartments.contains(f.code);
                    final c = f.acknowledged
                        ? AppColors.success
                        : missed
                            ? AppColors.error
                            : AppColors.warning;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            f.acknowledged
                                ? Icons.check_circle
                                : missed
                                    ? Icons.error
                                    : Icons.schedule,
                            size: 12,
                            color: c,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            f.acknowledged
                                ? '${f.code} · fitted'
                                : missed
                                    ? '${f.code} · MISSED'
                                    : '${f.code} · pending',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: c),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),

                // ── The production line ───────────────────────────────
                const Text('PRODUCTION LINE  ·  tap a stage to move the build',
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.disabled)),
                const SizedBox(height: 8),
                _lineStrip(r, busy),

                const SizedBox(height: 14),

                // ── Actions ───────────────────────────────────────────
                Row(
                  children: [
                    if (danger && r.rollbackStepId != null) ...[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => _moveTo(
                                    r,
                                    r.steps.firstWhere(
                                        (s) => s.stepId == r.rollbackStepId),
                                  ),
                          icon: const Icon(Icons.undo, size: 18),
                          // Named by department, never by step id.
                          label: Text(
                            'Send back to ${r.rollbackDepartmentName ?? r.rollbackDepartmentCode ?? _deptLabel(r, r.missedDepartments.first)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => _markReviewed(r),
                        icon: busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.done_all, size: 18),
                        label: const Text('Reviewed'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ),
                  ],
                ),

                // The one thing that must not be misunderstood.
                if (r.outstandingDepartments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 13, color: AppColors.disabled),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '"Reviewed" only clears this card. '
                          '${r.outstandingDepartments.join(', ')} must still '
                          'acknowledge fitting it before completing their step.',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.disabled),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The trailer's production line as a tappable strip.
  ///
  /// ● complete   ◉ build is here   ! owes this option
  /// Tapping a stage moves the build there — earlier = back, later = forward.
  Widget _lineStrip(PendingOptionReview r, bool busy) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: r.steps.length,
        separatorBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 22),
          child: Icon(Icons.chevron_right, size: 14, color: AppColors.divider),
        ),
        itemBuilder: (_, i) {
          final s = r.steps[i];
          final missed = s.owes && !s.isCurrent && _isPassed(s, r);

          final Color c = s.isCurrent
              ? AppColors.navy
              : missed
                  ? AppColors.error
                  : s.owes
                      ? AppColors.warning
                      : s.status == 'complete'
                          ? AppColors.success
                          : AppColors.disabled;

          return InkWell(
            onTap: busy || s.isCurrent ? null : () => _moveTo(r, s),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 78,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: c.withValues(alpha: s.isCurrent ? 0.14 : 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: c.withValues(alpha: s.isCurrent || missed ? 0.7 : 0.25),
                  width: s.isCurrent || missed ? 1.4 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    s.isCurrent
                        ? Icons.my_location
                        : missed
                            ? Icons.priority_high
                            : s.status == 'complete'
                                ? Icons.check
                                : Icons.circle_outlined,
                    size: 14,
                    color: c,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: c,
                    ),
                  ),
                  Text(
                    s.isCurrent
                        ? 'HERE'
                        : missed
                            ? 'MISSED'
                            : s.owes
                                ? 'owes'
                                : s.status == 'complete'
                                    ? 'done'
                                    : '',
                    style: TextStyle(fontSize: 8.5, color: c),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// This stage sits before the stage the build is currently on.
  bool _isPassed(OptionStep s, PendingOptionReview r) {
    final current = r.steps.where((x) => x.isCurrent).firstOrNull;
    if (current == null) return s.status == 'complete';
    return s.stepOrder < current.stepOrder;
  }
}

extension _StepPos on OptionStep {
  /// This stage is after the one the build is on.
  bool isAfterCurrent(PendingOptionReview r) {
    final current = r.steps.where((x) => x.isCurrent).firstOrNull;
    if (current == null) return false;
    return stepOrder > current.stepOrder;
  }
}
