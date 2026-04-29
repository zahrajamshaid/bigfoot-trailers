import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/delivery.dart';
import '../../../data/models/user.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/deliveries_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';

class DeliveryListScreen extends StatefulWidget {
  const DeliveryListScreen({super.key});

  @override
  State<DeliveryListScreen> createState() => _DeliveryListScreenState();
}

class _DeliveryListScreenState extends State<DeliveryListScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['scheduled', 'in_transit', 'delivered', 'failed'];

  late final TabController _tabController;
  String? _deliveryType;
  int? _driverUserId;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (_tabController.indexIsChanging) return;
        _reload();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    final auth = context.read<AuthViewModel>().state;
    final user = auth is Authenticated ? auth.user : null;
    final forceDriverFilter =
        user?.role == UserRole.driver ? user?.id : _driverUserId;

    context.read<DeliveriesViewModel>().load(
          status: _tabs[_tabController.index],
          deliveryType: _deliveryType,
          driverUserId: forceDriverFilter,
          dateFrom: _range?.start.toIso8601String().split('T').first,
          dateTo: _range?.end.toIso8601String().split('T').first,
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthViewModel, AuthState>(
      builder: (context, authState) {
        final user = authState is Authenticated ? authState.user : null;
        final canCreate = user != null &&
            (user.role == UserRole.owner ||
                user.role == UserRole.transportManager);

        return Scaffold(
          floatingActionButton: canCreate
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    await context.pushNamed(RouteNames.deliveryCreate);
                    if (mounted) _reload();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create Delivery'),
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
                  unselectedLabelColor: AppColors.white.withValues(alpha: 0.7),
                  tabs: const [
                    Tab(text: 'Scheduled'),
                    Tab(text: 'In Transit'),
                    Tab(text: 'Completed'),
                    Tab(text: 'Failed'),
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
                        child: CircularProgressIndicator(color: AppColors.amber),
                      );
                    }
                    if (state is DeliveriesError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.error, size: 42),
                              const SizedBox(height: 12),
                              Text(state.message),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _reload,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (state is DeliveriesLoaded) {
                      if (state.deliveries.isEmpty) {
                        return const Center(child: Text('No deliveries found'));
                      }
                      return RefreshIndicator(
                        onRefresh: () async => _reload(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemBuilder: (context, index) {
                            final d = state.deliveries[index];
                            return _DeliveryCard(
                              delivery: d,
                              onTap: () async {
                                await context.pushNamed(
                                  RouteNames.deliveryDetail,
                                  pathParameters: {'id': d.id.toString()},
                                );
                                if (mounted) _reload();
                              },
                            );
                          },
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemCount: state.deliveries.length,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DropdownButton<String?>(
            value: selectedType,
            hint: const Text('Delivery Type'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All Types')),
              DropdownMenuItem(value: 'factory_pickup', child: Text('Factory Pickup')),
              DropdownMenuItem(value: 'single_pull', child: Text('Single Pull')),
              DropdownMenuItem(value: 'stack_to_dealer', child: Text('Stack to Dealer')),
              DropdownMenuItem(value: 'stack_to_location', child: Text('Stack to Location')),
            ],
            onChanged: onTypeChanged,
          ),
          if (canFilterDriver)
            SizedBox(
              width: 160,
              child: TextFormField(
                initialValue: selectedDriverId?.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Driver ID',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onFieldSubmitted: (v) => onDriverChanged(int.tryParse(v)),
              ),
            ),
          OutlinedButton.icon(
            onPressed: onDateRangeTap,
            icon: const Icon(Icons.date_range),
            label: Text(
              range == null
                  ? 'Date Range'
                  : '${range!.start.toIso8601String().split('T').first} - ${range!.end.toIso8601String().split('T').first}',
            ),
          ),
          if (onClearDates != null)
            TextButton(onPressed: onClearDates, child: const Text('Clear Dates')),
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
            Text('Destination: ${delivery.destinationLabel}'),
            const SizedBox(height: 4),
            Text('Driver: ${delivery.driverName}'),
          ],
        ),
      ),
    );
  }
}
