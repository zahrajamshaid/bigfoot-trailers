import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/delivery.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/deliveries_viewmodel.dart';
import '../../../shared/widgets/status_badge.dart';

class DriverDeliveryScreen extends StatefulWidget {
  const DriverDeliveryScreen({super.key});

  @override
  State<DriverDeliveryScreen> createState() => _DriverDeliveryScreenState();
}

class _DriverDeliveryScreenState extends State<DriverDeliveryScreen> {
  bool _loading = true;
  bool _busyDeliveryId = false;
  int? _actionDeliveryId;
  List<Delivery> _deliveries = const [];

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
      if (!mounted) return;
      if (state is DeliveriesLoaded) {
        setState(() => _deliveries = state.deliveries);
      } else if (state is DeliveriesError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load deliveries: ${state.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markDeparted(Delivery d) async {
    if (_busyDeliveryId) return;
    setState(() {
      _busyDeliveryId = true;
      _actionDeliveryId = d.id;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<DeliveriesViewModel>().markDeparted(d.id);
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to mark departed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyDeliveryId = false;
          _actionDeliveryId = null;
        });
      }
    }
  }

  Future<void> _openComplete(Delivery d) async {
    await context.pushNamed(
      RouteNames.deliveryComplete,
      pathParameters: {'id': d.id.toString()},
    );
    if (mounted) await _load();
  }

  Future<void> _markFailed(Delivery d) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Mark Delivery Failed'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (reason == null || reason.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busyDeliveryId = true;
      _actionDeliveryId = d.id;
    });
    try {
      await context.read<DeliveriesViewModel>().markFailed(d.id, reason);
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to mark failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyDeliveryId = false;
          _actionDeliveryId = null;
        });
      }
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
    final active = _deliveries
        .where((d) => d.status != 'delivered' && d.status != 'failed')
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My Deliveries')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.amber),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: active.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text(
                            'No active deliveries assigned to you.\nPull down to refresh.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: active.length,
                      itemBuilder: (_, i) {
                        final d = active[i];
                        final busy = _busyDeliveryId && _actionDeliveryId == d.id;
                        return _DeliveryCard(
                          delivery: d,
                          busy: busy,
                          onTap: () => _openDetail(d),
                          onMarkDeparted: () => _markDeparted(d),
                          onComplete: () => _openComplete(d),
                          onMarkFailed: () => _markFailed(d),
                        );
                      },
                    ),
            ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final Delivery delivery;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onMarkDeparted;
  final VoidCallback onComplete;
  final VoidCallback onMarkFailed;

  const _DeliveryCard({
    required this.delivery,
    required this.busy,
    required this.onTap,
    required this.onMarkDeparted,
    required this.onComplete,
    required this.onMarkFailed,
  });

  @override
  Widget build(BuildContext context) {
    final d = delivery;
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
                Text('Destination: ${d.destinationLabel}'),
                const SizedBox(height: 12),
                _ActionRow(
                  status: d.status,
                  busy: busy,
                  onMarkDeparted: onMarkDeparted,
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

class _ActionRow extends StatelessWidget {
  final String status;
  final bool busy;
  final VoidCallback onMarkDeparted;
  final VoidCallback onComplete;
  final VoidCallback onMarkFailed;

  const _ActionRow({
    required this.status,
    required this.busy,
    required this.onMarkDeparted,
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

    if (status == 'scheduled') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: busy ? null : onMarkDeparted,
          icon: spinner ?? const Icon(Icons.local_shipping_outlined),
          label: const Text('Mark Departed'),
        ),
      );
    }

    if (status == 'in_transit') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : onComplete,
            icon: spinner ?? const Icon(Icons.task_alt_outlined),
            label: const Text('Complete Delivery'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onMarkFailed,
            icon: const Icon(Icons.report_gmailerrorred_outlined),
            label: const Text('Mark Failed'),
          ),
        ],
      );
    }

    // Fallback for any other status (e.g. unexpected backend value):
    // still let the driver open the detail view from the card tap.
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'No actions available for status: $status',
        style: const TextStyle(color: AppColors.disabled, fontSize: 12),
      ),
    );
  }
}
