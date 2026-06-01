import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/est_clock.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/delivery.dart';
import '../../../data/models/delivery_batch.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../utils/delivery_actions.dart';
import '../viewmodel/deliveries_viewmodel.dart';
import '../widgets/complete_delivery_dialog.dart';
import '../widgets/fail_reason_dialog.dart';
import '../../../shared/widgets/status_badge.dart';

/// Full-screen "My Deliveries" — a thin wrapper around [DriverDeliveryList]
/// for the driver's nav tab.
class DriverDeliveryScreen extends StatelessWidget {
  const DriverDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).driverDeliveriesTitle)),
      body: const DriverDeliveryList(),
    );
  }
}

/// The driver's deliveries — completed-today / this-week stats, an
/// Active/Completed toggle, and the matching list. Active deliveries carry the
/// Maps / Text / Complete / Mark Failed actions; completed ones are read-only
/// history the driver can scroll back through.
///
/// Self-contained (loads, refreshes, and scrolls on its own) so it can be
/// dropped both into [DriverDeliveryScreen] and onto the driver's dashboard.
class DriverDeliveryList extends StatefulWidget {
  const DriverDeliveryList({super.key});

  @override
  State<DriverDeliveryList> createState() => _DriverDeliveryListState();
}

class _DriverDeliveryListState extends State<DriverDeliveryList> {
  bool _loading = true;
  bool _showCompleted = false;
  int? _busyDeliveryId;
  int? _busyBatchId;
  List<Delivery> _deliveries = const [];
  List<DeliveryBatch> _myBatches = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return;
    final cubit = context.read<DeliveriesViewModel>();

    setState(() => _loading = true);
    try {
      await cubit.load(driverUserId: auth.user.id);
      final state = cubit.state;

      // Batches assigned to this driver that aren't finished yet — shown as
      // soon as they're created, no separate dispatch step needed.
      List<DeliveryBatch> myBatches = const [];
      try {
        final batches = await cubit.getBatches();
        myBatches = batches
            .where((b) =>
                b.driverUserId == auth.user.id && b.status != 'complete')
            .toList();
      } catch (_) {
        // Batches are a bonus on this screen — don't block the delivery list.
      }

      if (!mounted) return;
      if (state is DeliveriesLoaded) {
        setState(() {
          _deliveries = state.deliveries;
          _myBatches = myBatches;
        });
      } else if (state is DeliveriesError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).driverDeliveriesLoadFail(state.message))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeBatch(DeliveryBatch b) async {
    final l = AppLocalizations.of(context);
    final count = (b.deliveries ?? const []).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deliveryDetailCompleteBatchTitle),
        content: Text(l.driverCompleteBatchBody(
            count,
            b.batchNumber,
            b.destinationLocation?.name ??
                b.destinationName ??
                l.driverTheDestination)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deliveryDetailMarkAllDelivered),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyBatchId = b.id);
    try {
      await context.read<DeliveriesViewModel>().completeBatch(b.id);
      if (mounted) await _load();
      messenger.showSnackBar(
        SnackBar(content: Text(l.deliveryDetailBatchAllDelivered(b.batchNumber))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.deliveryDetailBatchFail('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  /// Complete a single trailer inside a batch (the rest stay in transit).
  Future<void> _completeBatchTrailer(
      DeliveryBatch b, BatchDeliveryItem item) async {
    final l = AppLocalizations.of(context);
    final so = item.trailer?.soNumber ?? '#${item.trailerId}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.driverCompleteTrailerTitle),
        content: Text(l.driverCompleteTrailerBody(so)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.driverMarkDelivered),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyBatchId = b.id);
    try {
      await context.read<DeliveriesViewModel>().completeDelivery(item.id);
      if (mounted) await _load();
      messenger.showSnackBar(SnackBar(content: Text(l.driverTrailerDelivered(so))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonFailed('$e'))));
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  /// Mark a single trailer inside a batch as failed.
  Future<void> _failBatchTrailer(
      DeliveryBatch b, BatchDeliveryItem item) async {
    final l = AppLocalizations.of(context);
    final so = item.trailer?.soNumber ?? '#${item.trailerId}';
    final reason = await showFailReasonDialog(context, title: l.driverMarkSoFailed(so));
    if (reason == null || reason.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyBatchId = b.id);
    try {
      await context.read<DeliveriesViewModel>().markFailed(item.id, reason);
      if (mounted) await _load();
      messenger.showSnackBar(SnackBar(content: Text(l.driverSoMarkedFailed(so))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonFailed('$e'))));
    } finally {
      if (mounted) setState(() => _busyBatchId = null);
    }
  }

  Future<void> _openMaps(Delivery d) async {
    final ok = await openDeliveryInMaps(d);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).deliveryDetailNoAddress)),
      );
    }
  }

  Future<void> _textCustomer(Delivery d) async {
    final ok = await textDeliveryCustomer(d);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).deliveryDetailNoPhone)),
      );
    }
  }

  Future<void> _complete(Delivery d) async {
    final result = await showCompleteDeliveryDialog(context, d);
    if (result == null || !mounted) return;
    final l = AppLocalizations.of(context);

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyDeliveryId = d.id);
    try {
      await context.read<DeliveriesViewModel>().completeDelivery(
            d.id,
            paymentCollected: result.paymentCollected,
          );
      if (mounted) await _load();
      messenger.showSnackBar(
        SnackBar(content: Text(l.driverTrailerDelivered(d.soNumber))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.deliveryDetailCompleteFail('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busyDeliveryId = null);
    }
  }

  Future<void> _markFailed(Delivery d) async {
    final l = AppLocalizations.of(context);
    final reason =
        await showFailReasonDialog(context, title: l.deliveryDetailMarkFailedTitle);

    if (!mounted) return;
    if (reason == null || reason.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyDeliveryId = d.id);
    try {
      await context.read<DeliveriesViewModel>().markFailed(d.id, reason);
      if (mounted) await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.deliveryDetailMarkFailedError('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busyDeliveryId = null);
    }
  }

  Future<void> _openDetail(Delivery d) async {
    await context.pushNamed(
      RouteNames.deliveryDetail,
      pathParameters: {'id': d.id.toString()},
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.amber),
      );
    }

    // Batched deliveries are rendered inside their _BatchCard, so exclude
    // them here to avoid double-showing as standalone _DeliveryCard rows.
    final active = _deliveries
        .where((d) =>
            d.status != 'delivered' &&
            d.status != 'failed' &&
            d.deliveryBatchId == null)
        .toList();

    final completed = _deliveries
        .where((d) => d.status == 'delivered' && d.deliveryBatchId == null)
        .toList()
      ..sort((a, b) => (b.deliveredAt ?? DateTime(0))
          .compareTo(a.deliveredAt ?? DateTime(0)));

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final completedToday = completed
        .where((d) => d.deliveredAt != null && _isSameDay(d.deliveredAt!, now))
        .length;
    final completedWeek = completed
        .where((d) =>
            d.deliveredAt != null && d.deliveredAt!.toLocal().isAfter(weekAgo))
        .length;

    final shown = _showCompleted ? completed : active;
    final activeCount = active.length + _myBatches.length;
    final activeEmpty = active.isEmpty && _myBatches.isEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: AppLocalizations.of(context).driverCompletedToday,
                  value: completedToday,
                  icon: Icons.today_outlined,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  label: AppLocalizations.of(context).dashStatCompletedThisWeek,
                  value: completedWeek,
                  icon: Icons.date_range_outlined,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text('${AppLocalizations.of(context).statusActive} ($activeCount)'),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                    '${AppLocalizations.of(context).deliveryListTabCompleted} (${completed.length})'),
                icon: const Icon(Icons.history, size: 18),
              ),
            ],
            selected: {_showCompleted},
            onSelectionChanged: (s) =>
                setState(() => _showCompleted = s.first),
          ),
          const SizedBox(height: 14),
          if (_showCompleted && shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Center(
                  child: Text(AppLocalizations.of(context).deliveryListEmpty)),
            )
          else if (!_showCompleted && activeEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 64),
              child: Center(
                child: Text(
                  AppLocalizations.of(context).deliveryListEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else if (_showCompleted)
            ...shown.map(
              (d) => _CompletedCard(
                delivery: d,
                onTap: () => _openDetail(d),
              ),
            )
          else ...[
            // Batch deliveries — one card, completed as a unit.
            ..._myBatches.map(
              (b) => _BatchCard(
                batch: b,
                busy: _busyBatchId == b.id,
                onComplete: () => _completeBatch(b),
                onCompleteTrailer: (item) => _completeBatchTrailer(b, item),
                onFailTrailer: (item) => _failBatchTrailer(b, item),
              ),
            ),
            ...active.map(
              (d) => _DeliveryCard(
                delivery: d,
                busy: _busyDeliveryId == d.id,
                onTap: () => _openDetail(d),
                onOpenMaps: () => _openMaps(d),
                onTextCustomer: () => _textCustomer(d),
                onComplete: () => _complete(d),
                onMarkFailed: () => _markFailed(d),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    return la.year == b.year && la.month == b.month && la.day == b.day;
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.disabled),
          ),
        ],
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  final Delivery delivery;
  final VoidCallback onTap;

  const _CompletedCard({required this.delivery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final d = delivery;
    final date = d.deliveredAt != null
        ? EstClock.date(d.deliveredAt!)
        : l.stockInventoryUnknownDate;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.soNumber,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusBadge(status: d.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(d.modelName,
                    style: const TextStyle(color: AppColors.disabled)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.event_available_outlined,
                        size: 15, color: AppColors.disabled),
                    const SizedBox(width: 4),
                    Text(l.driverDeliveredOn(date),
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
                if (d.deliveryType == 'factory_pickup' &&
                    d.pickedUpByName != null &&
                    d.pickedUpByName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 15, color: AppColors.disabled),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Picked up by: ${d.pickedUpByName}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onOpenMaps;
  final VoidCallback onTextCustomer;
  final VoidCallback onComplete;
  final VoidCallback onMarkFailed;

  const _DeliveryCard({
    required this.delivery,
    required this.busy,
    required this.onTap,
    required this.onOpenMaps,
    required this.onTextCustomer,
    required this.onComplete,
    required this.onMarkFailed,
  });

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final hasPhone = deliveryHasCustomerPhone(d);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.soNumber,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusBadge(status: d.status),
                  ],
                ),
                const SizedBox(height: 6),
                Text(d.modelName),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 16, color: AppColors.disabled),
                    const SizedBox(width: 4),
                    Expanded(child: Text(d.destinationLabel)),
                  ],
                ),
                if (d.deliveryType == 'factory_pickup' &&
                    d.pickedUpByName != null &&
                    d.pickedUpByName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 16, color: AppColors.disabled),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text('Picked up by: ${d.pickedUpByName}'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Navigation + comms
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : onOpenMaps,
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(AppLocalizations.of(context).deliveryDetailOpenMaps),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy || !hasPhone ? null : onTextCustomer,
                        icon: const Icon(Icons.sms_outlined, size: 18),
                        label: Text(AppLocalizations.of(context).deliveryDetailTextCustomer),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Outcome
                _OutcomeRow(
                  busy: busy,
                  onComplete: onComplete,
                  onMarkFailed: onMarkFailed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  final bool busy;
  final VoidCallback onComplete;
  final VoidCallback onMarkFailed;

  const _OutcomeRow({
    required this.busy,
    required this.onComplete,
    required this.onMarkFailed,
  });

  @override
  Widget build(BuildContext context) {
    final spinner = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onComplete,
          icon: spinner ?? const Icon(Icons.task_alt_outlined),
          label: Text(AppLocalizations.of(context).deliveryDetailCompleteAction),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onMarkFailed,
          icon: const Icon(Icons.report_gmailerrorred_outlined),
          label: Text(AppLocalizations.of(context).deliveryDetailMarkFailed),
        ),
      ],
    );
  }
}

/// An in-transit delivery batch on the driver's list. The whole batch can be
/// completed with one tap, or any single trailer completed/failed on its own.
class _BatchCard extends StatelessWidget {
  final DeliveryBatch batch;
  final bool busy;
  final VoidCallback onComplete;
  final void Function(BatchDeliveryItem) onCompleteTrailer;
  final void Function(BatchDeliveryItem) onFailTrailer;

  const _BatchCard({
    required this.batch,
    required this.busy,
    required this.onComplete,
    required this.onCompleteTrailer,
    required this.onFailTrailer,
  });

  @override
  Widget build(BuildContext context) {
    final deliveries = batch.deliveries ?? const [];
    final destination =
        batch.destinationLocation?.name ?? batch.destinationName ?? '-';
    bool isOpen(String s) => s == 'scheduled' || s == 'in_transit';
    final anyOpen = deliveries.any((d) => isOpen(d.status));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 20, color: AppColors.navy),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    batch.batchNumber,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                      AppLocalizations.of(context)
                          .deliveryDetailTrailerCount(deliveries.length)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 16, color: AppColors.disabled),
                const SizedBox(width: 4),
                Expanded(child: Text(destination)),
              ],
            ),
            const SizedBox(height: 8),
            // Per-trailer rows — each can be completed or failed on its own.
            ...deliveries.map((d) {
              final so = d.trailer?.soNumber ?? '#${d.trailerId}';
              final open = isOpen(d.status);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(so)),
                    StatusBadge(status: d.status),
                    if (open)
                      PopupMenuButton<String>(
                        enabled: !busy,
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (v) {
                          if (v == 'complete') onCompleteTrailer(d);
                          if (v == 'fail') onFailTrailer(d);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'complete',
                            child: Text(AppLocalizations.of(context).driverMarkDelivered),
                          ),
                          PopupMenuItem(
                            value: 'fail',
                            child: Text(AppLocalizations.of(context).deliveryDetailMarkFailed),
                          ),
                        ],
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.success),
                onPressed: busy || !anyOpen ? null : onComplete,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.task_alt_outlined),
                label: Text(AppLocalizations.of(context).deliveryDetailCompleteBatchTitle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
