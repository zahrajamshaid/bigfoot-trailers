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
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _deliveries.where((d) => d.status != 'delivered' && d.status != 'failed').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('My Deliveries')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: active.length,
                itemBuilder: (_, i) {
                  final d = active[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                              child: Text(d.soNumber,
                                  style: const TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w700)),
                            ),
                            StatusBadge(status: d.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(d.modelName),
                        Text('Destination: ${d.destinationLabel}'),
                        const SizedBox(height: 12),
                        if (d.status == 'scheduled')
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () async {
                                await context.read<DeliveriesViewModel>().markDeparted(d.id);
                                if (mounted) _load();
                              },
                              child: const Text('Departed'),
                            ),
                          ),
                        if (d.status == 'in_transit')
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () async {
                                await context.pushNamed(
                                  RouteNames.deliveryComplete,
                                  pathParameters: {'id': d.id.toString()},
                                );
                                if (mounted) _load();
                              },
                              child: const Text('Delivered'),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
