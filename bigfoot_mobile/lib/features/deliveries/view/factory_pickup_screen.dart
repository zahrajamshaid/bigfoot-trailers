import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/delivery.dart';
import '../viewmodel/deliveries_viewmodel.dart';

class FactoryPickupScreen extends StatefulWidget {
  const FactoryPickupScreen({super.key});

  @override
  State<FactoryPickupScreen> createState() => _FactoryPickupScreenState();
}

class _FactoryPickupScreenState extends State<FactoryPickupScreen> {
  bool _loading = true;
  List<Delivery> _deliveries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<DeliveriesViewModel>();
    setState(() => _loading = true);
    try {
      await cubit.load(status: 'scheduled', deliveryType: 'factory_pickup');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Factory Pickups')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemBuilder: (_, i) {
                  final d = _deliveries[i];
                  return Card(
                    child: ListTile(
                      title: Text(d.soNumber),
                      subtitle: Text('${d.modelName} • ${d.customerName}'),
                      trailing: FilledButton(
                        onPressed: () async {
                          await context.read<DeliveriesViewModel>().completeFactoryPickup(d.id);
                          if (mounted) _load();
                        },
                        child: const Text('Customer Picked Up'),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: _deliveries.length,
              ),
            ),
    );
  }
}
