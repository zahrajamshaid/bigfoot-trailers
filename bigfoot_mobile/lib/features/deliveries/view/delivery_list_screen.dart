import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/delivery.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/deliveries_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';

class DeliveryListScreen extends StatefulWidget {
  /// Optional status that preselects the matching tab on open — set by
  /// dashboard deep links such as `?status=in_transit`.
  final String? initialStatus;

  const DeliveryListScreen({super.key, this.initialStatus});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['scheduled', 'delivered', 'failed'];

  late final TabController _tabController;
  late final VoidCallback _tabListener;
  String? _deliveryType;
  int? _driverUserId;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _tabListener = () {
      if (_tabController.indexIsChanging) return;
      if (!mounted) return;
      _reload();
    };
    final initialIndex = _tabs.indexOf(widget.initialStatus ?? '');
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    )..addListener(_tabListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _tabController.removeListener(_tabListener);
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final auth = context.read<AuthViewModel>().state;
    final user = auth is Authenticated ? auth.user : null;
    final forceDriverFilter = user?.role == UserRole.driver
        ? user?.id
        : _driverUserId;

    context.read<DeliveriesViewModel>().load(
      status: _tabs[_tabController.index],
      deliveryType: _deliveryType,
      driverUserId: forceDriverFilter,
      dateFrom: _range?.start.toIso8601String().split('T').first,
      dateTo: _range?.end.toIso8601String().split('T').first,
    );
  }

  /// Collapses deliveries sharing a batch into one `List<Delivery>` row;
  /// standalone deliveries stay as a plain `Delivery`. Order is preserved —
  /// a batch appears where its first delivery would.
  List<Object> _groupByBatch(List<Delivery> deliveries) {
    final groups = <int, List<Delivery>>{};
    for (final d in deliveries) {
      final bid = d.deliveryBatchId;
      if (bid != null) groups.putIfAbsent(bid, () => []).add(d);
    }
    final rows = <Object>[];
    final seen = <int>{};
    for (final d in deliveries) {
      final bid = d.deliveryBatchId;
      if (bid != null) {
        if (seen.add(bid)) rows.add(groups[bid]!);
      } else {
        rows.add(d);
      }
    }
    return rows;
  }

  Future<void> _openDetail(Delivery d) async {
    await context.pushNamed(
      RouteNames.deliveryDetail,
      pathParameters: {'id': d.id.toString()},
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocBuilder<AuthViewModel, AuthState>(
      builder: (context, authState) {
        final user = authState is Authenticated ? authState.user : null;
        final canCreate =
            user != null &&
            (user.role == UserRole.owner ||
                user.role == UserRole.transportManager);

        return Scaffold(
          floatingActionButton: canCreate
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'batchesFab',
                      backgroundColor: AppColors.navy,
                      onPressed: () async {
                        await context.pushNamed(RouteNames.deliveryBatches);
                        if (mounted) _reload();
                      },
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(l.deliveryListFabBatches),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'createDeliveryFab',
                      onPressed: () async {
                        await context.pushNamed(RouteNames.deliveryCreate);
                        if (mounted) _reload();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l.deliveryListFabCreate),
                    ),
                  ],
                )
              : null,
          body: Column(
            children: [
              Material(
                color: AppColors.navy,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.amber,
                  labelColor: AppColors.white,
                  unselectedLabelColor:
                      AppColors.white.withValues(alpha: 0.7),
                  tabs: [
                    Tab(text: l.deliveryListTabScheduled),
                    Tab(text: l.deliveryListTabCompleted),
                    Tab(text: l.deliveryListTabFailed),
                  ],
                ),
              ),
              _FilterBar(
                selectedType: _deliveryType,
                selectedDriverId: _driverUserId,
                range: _range,
                canFilterDriver: user?.role != UserRole.driver,
                onTypeChanged: (v) {
                  setState(() => _deliveryType = v);
                  _reload();
                },
                onDriverChanged: (v) {
                  setState(() => _driverUserId = v);
                  _reload();
                },
                onDateRangeTap: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange: _range,
                  );
                  if (picked != null) {
                    setState(() => _range = picked);
                    _reload();
                  }
                },
                onClearDates: _range == null
                    ? null
                    : () {
                        setState(() => _range = null);
                        _reload();
                      },
              ),
              Expanded(
                child: BlocBuilder<DeliveriesViewModel, DeliveriesState>(
                  builder: (context, state) {
                    if (state is DeliveriesLoading) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.amber,
                        ),
                      );
                    }
                    if (state is DeliveriesError) {
                      return Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppColors.error,
                                size: 42,
                              ),
                              const SizedBox(height: 12),
                              Text(state.message),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _reload,
                                child: Text(l.commonRetry),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (state is DeliveriesLoaded) {
                      if (state.deliveries.isEmpty) {
                        return Center(child: Text(l.deliveryListEmpty));
                      }
                      // Deliveries that share a batch are shown as one card so
                      // it's clear which trailers travel together.
                      final rows = _groupByBatch(state.deliveries);
                      return RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            if (row is List<Delivery>) {
                              return _BatchGroupCard(
                                deliveries: row,
                                onTapDelivery: _openDetail,
                              );
                            }
                            return _DeliveryCard(
                              delivery: row as Delivery,
                              onTap: () => _openDetail(row),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemCount: rows.length,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String? selectedType;
  final int? selectedDriverId;
  final DateTimeRange? range;
  final bool canFilterDriver;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<int?> onDriverChanged;
  final VoidCallback onDateRangeTap;
  final VoidCallback? onClearDates;

  const _FilterBar({
    required this.selectedType,
    required this.selectedDriverId,
    required this.range,
    required this.canFilterDriver,
    required this.onTypeChanged,
    required this.onDriverChanged,
    required this.onDateRangeTap,
    this.onClearDates,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DropdownButton<String?>(
            value: selectedType,
            hint: Text(l.deliveryListFilterType),
            items: [
              DropdownMenuItem(value: null, child: Text(l.deliveryListFilterAllTypes)),
              DropdownMenuItem(
                value: 'factory_pickup',
                child: Text(l.deliveryListFilterFactoryPickup),
              ),
              DropdownMenuItem(
                value: 'single_pull',
                child: Text(l.deliveryListFilterSinglePull),
              ),
              DropdownMenuItem(
                value: 'stack_to_dealer',
                child: Text(l.deliveryListFilterStackToDealer),
              ),
              DropdownMenuItem(
                value: 'stack_to_location',
                child: Text(l.deliveryListFilterStackToLocation),
              ),
            ],
            onChanged: onTypeChanged,
          ),
          if (canFilterDriver)
            SizedBox(
              width: 160,
              child: TextFormField(
                initialValue: selectedDriverId?.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.deliveryListFilterDriverId,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onFieldSubmitted: (v) => onDriverChanged(int.tryParse(v)),
              ),
            ),
          OutlinedButton.icon(
            onPressed: onDateRangeTap,
            icon: const Icon(Icons.date_range),
            label: Text(
              range == null
                  ? l.deliveryListFilterDateRange
                  : '${range!.start.toIso8601String().split('T').first} - ${range!.end.toIso8601String().split('T').first}',
            ),
          ),
          if (onClearDates != null)
            TextButton(
              onPressed: onClearDates,
              child: Text(l.deliveryListFilterClearDates),
            ),
        ],
      ),
    );
  }
}

/// One card for a whole batch — lists every trailer in it. Tapping a trailer
/// opens that delivery's detail.
class _BatchGroupCard extends StatelessWidget {
  final List<Delivery> deliveries;
  final void Function(Delivery) onTapDelivery;

  const _BatchGroupCard({
    required this.deliveries,
    required this.onTapDelivery,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 18, color: AppColors.navy),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)
                        .deliveryListBatchTitle(deliveries.length),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...deliveries.map(
            (d) => InkWell(
              onTap: () => onTapDelivery(d),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.soNumber,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            d.modelName,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.disabled),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(status: d.status),
                    const Icon(Icons.chevron_right, color: AppColors.disabled),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final VoidCallback onTap;

  const _DeliveryCard({required this.delivery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    delivery.soNumber,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                StatusBadge(status: delivery.status),
              ],
            ),
            const SizedBox(height: 8),
            Text('${delivery.modelName} • ${delivery.customerName}'),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context)
                .deliveryListDestination(delivery.destinationLabel)),
            const SizedBox(height: 4),
            Text(AppLocalizations.of(context)
                .deliveryListDriverLabel(delivery.driverName)),
            if (delivery.deliveryType == 'factory_pickup' &&
                delivery.pickedUpByName != null &&
                delivery.pickedUpByName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: AppColors.disabled),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Picked up by: ${delivery.pickedUpByName}'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
