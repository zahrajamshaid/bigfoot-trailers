import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../data/models/queue_item.dart';
import '../../../data/models/department.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/ownership_chip.dart';
import '../../../shared/widgets/stall_reason_chip.dart';

/// All-departments queue view for production_manager and owner.
/// Horizontal tabs per department with drag-to-reorder support.
class AllQueuesScreen extends StatefulWidget {
  const AllQueuesScreen({super.key});

  @override
  State<AllQueuesScreen> createState() => _AllQueuesScreenState();
}

class _AllQueuesScreenState extends State<AllQueuesScreen>
    with TickerProviderStateMixin {
  late final DioClient _api;
  TabController? _tabController;
  List<Department> _departments = [];
  Map<int, List<QueueItem>> _queues = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = context.read<DioClient>();
    _loadAll();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch departments
      final deptResp = await _api.get<List<dynamic>>(
        ApiEndpoints.adminDepartments,
        fromJson: (d) => d as List<dynamic>,
      );
      final allDepts = (deptResp.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Department.fromJson)
          .where((d) => !d.isQcStep) // production departments only
          .toList();

      // Fetch queue for each department
      final queues = <int, List<QueueItem>>{};
      for (final dept in allDepts) {
        try {
          final resp = await _api.get<List<dynamic>>(
            ApiEndpoints.productionQueue(dept.id),
            fromJson: (d) => d as List<dynamic>,
          );
          queues[dept.id] = (resp.data ?? [])
              .whereType<Map<String, dynamic>>()
              .map(QueueItem.fromJson)
              .toList();
        } catch (_) {
          queues[dept.id] = [];
        }
      }

      if (!mounted) return;

      _tabController?.dispose();
      _tabController = TabController(length: allDepts.length, vsync: this);

      setState(() {
        _departments = allDepts;
        _queues = queues;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = e.displayMessage; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = AppLocalizations.of(context).allQueuesLoadFail; });
    }
  }

  Future<void> _onReorder(int departmentId, int oldIndex, int newIndex) async {
    final queue = List<QueueItem>.from(_queues[departmentId] ?? []);
    if (newIndex > oldIndex) newIndex--;
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);

    setState(() => _queues[departmentId] = queue);

    try {
      final stepIds = queue.map((q) => q.stepId).toList();
      await _api.patch<Map<String, dynamic>>(
        ApiEndpoints.reorderQueue(departmentId),
        data: {'stepIds': stepIds},
        fromJson: (d) => d as Map<String, dynamic>,
      );
    } catch (e) {
      // Revert on failure
      _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).allQueuesReorderFail)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadAll, child: Text(l.commonRetry)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.allQueuesTitle),
      ),
      body: Column(
        children: [
          // Summary bar
          _SummaryBar(departments: _departments, queues: _queues),
          // Tab bar
          if (_tabController != null && _departments.isNotEmpty)
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.navy,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.amber,
              tabs: _departments.map((d) {
                final count = _queues[d.id]?.length ?? 0;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(d.code),
                      if (count > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          // Tab content
          if (_tabController != null && _departments.isNotEmpty)
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _departments.map((dept) {
                  final queue = _queues[dept.id] ?? [];
                  if (queue.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 48, color: AppColors.success),
                          const SizedBox(height: 8),
                          Text(l.allQueuesEmpty,
                              style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _loadAll,
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: queue.length,
                      onReorder: (old, newIdx) => _onReorder(dept.id, old, newIdx),
                      itemBuilder: (context, index) {
                        final item = queue[index];
                        return _AllQueueCard(
                          key: ValueKey(item.stepId),
                          item: item,
                          onTap: () => context.push('/trailers/${item.trailerId}'),
                        );
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final List<Department> departments;
  final Map<int, List<QueueItem>> queues;

  const _SummaryBar({required this.departments, required this.queues});

  @override
  Widget build(BuildContext context) {
    final entries = departments
        .where((d) => (queues[d.id]?.length ?? 0) > 0)
        .map((d) => '${d.code}: ${queues[d.id]!.length}')
        .join(' | ');

    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.navy.withValues(alpha: 0.05),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          entries,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.navy,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _AllQueueCard extends StatelessWidget {
  final QueueItem item;
  final VoidCallback onTap;

  const _AllQueueCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final stallLevel = item.stallLevel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 5,
                  color: item.isHot || stallLevel >= 2
                      ? AppColors.error
                      : stallLevel == 1
                          ? AppColors.warning
                          : AppColors.navy,
                ),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        // SO + model + ownership + reason chips.
                        //
                        // The numeric queue position circle was dropped — on
                        // the manager all-queues view the drag handle on the
                        // right already conveys "this is the ordering" and
                        // the integer offered no actionable information.
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    item.soNumber,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  if (item.series != null)
                                    SeriesBadge(series: item.series!),
                                  OwnershipChip.fromSignals(
                                    customerName: item.customerName,
                                    isStockBuild: item.isStockBuild,
                                    soldToName: item.soldToName,
                                    dense: true,
                                  ),
                                  if (item.isHot || stallLevel >= 1)
                                    StallReasonChip(
                                      isHot: item.isHot,
                                      stallLevel: stallLevel,
                                      hoursInQueue:
                                          item.calculatedHoursInQueue,
                                      dense: true,
                                    ),
                                  if (item.isRework)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: AppColors.warning
                                                .withValues(alpha: 0.4)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.replay,
                                              size: 11,
                                              color: AppColors.warning),
                                          const SizedBox(width: 3),
                                          Text(
                                            AppLocalizations.of(context)
                                                .queueReworkBadge(
                                                    item.reworkCount),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.warning,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (item.modelName != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    item.modelName!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Drag handle — primary affordance for manager
                        // ordering on this view.
                        const Icon(Icons.drag_handle,
                            color: Colors.grey, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
