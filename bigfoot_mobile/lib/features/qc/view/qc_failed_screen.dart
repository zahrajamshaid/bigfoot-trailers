import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/est_clock.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/status_badge.dart';

/// Drilldown behind the QC dashboard's fail-rate tile. Lists every failed
/// QC inspection over the rolling 14-day window with the trailer + dept
/// context so the inspector can quickly see which builds are tripping
/// which checks. Older failures are still on each trailer's history page
/// (and in the audit log) — they just don't clutter this view.
class QcFailedScreen extends StatefulWidget {
  const QcFailedScreen({super.key});

  @override
  State<QcFailedScreen> createState() => _QcFailedScreenState();
}

class _QcFailedScreenState extends State<QcFailedScreen> {
  static const int _windowDays = 14;

  late Future<List<FailedInspectionItem>> _future;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<FailedInspectionItem>> _load() {
    final repo = context.read<QcRepository>();
    return repo.getFailedInspections(days: _windowDays);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  /// Client-side filter — the 14-day window is small enough that filtering
  /// in-memory is cheaper than a round-trip per keystroke. Matches on SO,
  /// failing department (code OR display name), inspector name, model name,
  /// customer name, and the free-text fail notes.
  List<FailedInspectionItem> _filter(List<FailedInspectionItem> items) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((it) {
      bool m(String? s) => (s ?? '').toLowerCase().contains(q);
      return m(it.soNumber) ||
          m(it.stepDeptCode) ||
          m(it.stepDeptName) ||
          m(it.inspectorName) ||
          m(it.modelName) ||
          m(it.customerName) ||
          m(it.failNotes);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Failed QC inspections')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search SO, department, inspector, notes',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          // Tiny header so it's obvious the list is bounded — answers "why
          // don't I see that failure from last month?" without anyone
          // needing to ask.
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Last $_windowDays days · older failures live on each trailer\'s history',
                style: TextStyle(fontSize: 11, color: AppColors.disabled),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<FailedInspectionItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  final msg = snap.error is ApiException
                      ? (snap.error as ApiException).displayMessage
                      : snap.error.toString();
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: AppColors.error),
                          const SizedBox(height: 16),
                          Text(msg, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: Text(l.commonRetry),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final all = snap.data ?? const [];
                final filtered = _filter(all);
                if (all.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.celebration_outlined,
                              size: 56, color: AppColors.success),
                          SizedBox(height: 12),
                          Text(
                            'No failed QC inspections in the last 14 days.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (filtered.isEmpty) {
                  // We have data but the search box filtered it all out —
                  // empty-state explains it so the user doesn't think the
                  // list is broken.
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.search_off,
                              size: 48, color: AppColors.disabled),
                          SizedBox(height: 12),
                          Text(
                            'No matches for the current search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.disabled),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _FailRow(item: filtered[i]),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FailRow extends StatelessWidget {
  final FailedInspectionItem item;
  const _FailRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateLabel = item.inspectedAt != null
        ? EstClock.dateTime(item.inspectedAt!)
        : '—';
    final deptLabel = item.stepDeptName ?? item.stepDeptCode ?? '—';
    final reworkLabel =
        item.reworkTargetName ?? item.reworkTargetCode;
    final attemptSuffix = item.attemptNumber > 1
        ? ' · attempt ${item.attemptNumber}'
        : '';
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.pushNamed(
          RouteNames.trailerDetail,
          pathParameters: {'id': item.trailerId.toString()},
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.soNumber,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  if (item.series != null && item.series!.isNotEmpty)
                    SeriesBadge(series: item.series!),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${item.modelName ?? '—'}'
                '${item.customerName != null ? ' • ${item.customerName}' : ''}',
                style: const TextStyle(color: AppColors.disabled),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.cancel_outlined,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Failed at $deptLabel$attemptSuffix',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.error),
                    ),
                  ),
                ],
              ),
              if (reworkLabel != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.undo_outlined,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Rework → $reworkLabel',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ],
              if ((item.failNotes ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(item.failNotes!,
                    style: const TextStyle(fontSize: 13)),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 13, color: AppColors.disabled),
                  const SizedBox(width: 4),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.disabled),
                  ),
                  if (item.inspectorName != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.person_outline,
                        size: 13, color: AppColors.disabled),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        item.inspectorName!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.disabled),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
