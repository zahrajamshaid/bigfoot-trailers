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

class DeliveryDetailScreen extends StatefulWidget {
  final int deliveryId;

  const DeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  Delivery? _delivery;
  bool _loading = true;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<DeliveriesViewModel>().getById(widget.deliveryId);
      if (!mounted) return;
      setState(() => _delivery = d);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.amber)),
      );
    }

    final d = _delivery;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery Detail')),
        body: const Center(child: Text('Delivery not found')),
      );
    }

    final auth = context.read<AuthViewModel>().state;
    final role = auth is Authenticated ? auth.user.role : '';
    final canDepart = d.status == 'scheduled' &&
        (role == UserRole.driver || role == UserRole.transportManager);
    final canComplete = d.status == 'in_transit' &&
        (role == UserRole.driver || role == UserRole.transportManager);
    final canFail = role == UserRole.driver || role == UserRole.transportManager;

    return Scaffold(
      appBar: AppBar(title: Text('Delivery #${d.id}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _TimelineHeader(status: d.status),
            const SizedBox(height: 14),
            _SectionCard(
              title: 'Trailer',
              children: [
                Text('SO: ${d.soNumber}'),
                Text('Model: ${d.modelName}'),
                Text('Customer: ${d.customerName}'),
              ],
            ),
            _SectionCard(
              title: 'Driver',
              children: [Text('Assigned: ${d.driverName}')],
            ),
            _SectionCard(
              title: 'Destination',
              children: [
                Text(d.destinationLabel),
                if (d.destinationLocation != null &&
                    d.destinationLocation!.city != null)
                  Text('${d.destinationLocation!.city}, ${d.destinationLocation!.state ?? ''}'),
              ],
            ),
            _SectionCard(
              title: 'Payment',
              children: [
                Text('Balance due: ${_money(d.balanceDue)}'),
                Text('Collected: ${_money(d.paymentCollected)}'),
                Text('Method: ${d.paymentMethod ?? '-'}'),
              ],
            ),
            _SectionCard(
              title: 'Photos',
              trailing: Text('${d.deliveryPhotos?.length ?? 0} uploaded'),
              children: [
                if ((d.deliveryPhotos ?? []).isEmpty)
                  const Text('No proof-of-delivery photos yet'),
                if ((d.deliveryPhotos ?? []).isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: d.deliveryPhotos!
                        .map(
                          (p) => Container(
                            width: 78,
                            height: 78,
                            color: AppColors.background,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_outlined),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (canDepart)
                  FilledButton.icon(
                    onPressed: _actionBusy ? null : _markDeparted,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Mark Departed'),
                  ),
                if (canComplete)
                  FilledButton.icon(
                    onPressed: _actionBusy
                        ? null
                        : () async {
                            await context.pushNamed(
                              RouteNames.deliveryComplete,
                              pathParameters: {'id': d.id.toString()},
                            );
                            if (mounted) _load();
                          },
                    icon: const Icon(Icons.task_alt_outlined),
                    label: const Text('Complete Delivery'),
                  ),
                if (canFail)
                  OutlinedButton.icon(
                    onPressed: _actionBusy ? null : _markFailed,
                    icon: const Icon(Icons.report_gmailerrorred),
                    label: const Text('Mark Failed'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _money(double? v) => v == null ? '-' : r'$ ' + v.toStringAsFixed(2);

  Future<void> _markDeparted() async {
    setState(() => _actionBusy = true);
    try {
      await context.read<DeliveriesViewModel>().markDeparted(widget.deliveryId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark departed: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _markFailed() async {
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
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
    setState(() => _actionBusy = true);
    try {
      await context.read<DeliveriesViewModel>().markFailed(widget.deliveryId, reason);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }
}

class _TimelineHeader extends StatelessWidget {
  final String status;

  const _TimelineHeader({required this.status});

  @override
  Widget build(BuildContext context) {
    final current = switch (status) {
      'scheduled' => 0,
      'in_transit' => 1,
      'delivered' => 2,
      _ => 0,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(3, (i) {
              final active = i <= current;
              return Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: active ? AppColors.success : AppColors.divider,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 11, color: AppColors.white)),
                    ),
                    if (i < 2)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i < current ? AppColors.success : AppColors.divider,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          const Row(
            children: [
              Expanded(child: Text('Scheduled', textAlign: TextAlign.left)),
              Expanded(child: Text('Departed', textAlign: TextAlign.center)),
              Expanded(child: Text('Delivered', textAlign: TextAlign.right)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
