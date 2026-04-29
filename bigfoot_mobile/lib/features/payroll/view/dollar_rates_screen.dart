import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/payroll_record.dart';
import '../viewmodel/payroll_viewmodel.dart';

class DollarRatesScreen extends StatefulWidget {
  const DollarRatesScreen({super.key});

  @override
  State<DollarRatesScreen> createState() => _DollarRatesScreenState();
}

class _DollarRatesScreenState extends State<DollarRatesScreen> {
  bool _loading = true;
  List<DollarRate> _rates = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rates = await context.read<PayrollViewModel>().getDollarRates();
      if (!mounted) return;
      setState(() => _rates = rates);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <int, List<DollarRate>>{};
    for (final r in _rates) {
      grouped.putIfAbsent(r.departmentId, () => []).add(r);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => (b.effectiveFrom ?? DateTime(1970)).compareTo(a.effectiveFrom ?? DateTime(1970)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dollar Rates'),
        actions: [
          IconButton(onPressed: _addRate, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: grouped.entries.map((entry) {
                final latest = entry.value.first;
                final deptName = latest.department?.displayName ?? 'Department ${entry.key}';
                return Card(
                  child: ExpansionTile(
                    title: Text(deptName),
                    subtitle: Text(
                      'Current: '
                      r'$ ${latest.dollarPerPoint.toStringAsFixed(2)} / point',
                    ),
                    children: [
                      ...entry.value.map(
                        (r) => ListTile(
                          dense: true,
                          title: Text(r'$ ${r.dollarPerPoint.toStringAsFixed(2)} / point'),
                          subtitle: Text(
                            'From ${r.effectiveFrom?.toIso8601String().split('T').first ?? '-'}'
                            ' to ${r.effectiveTo?.toIso8601String().split('T').first ?? 'present'}',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Future<void> _addRate() async {
    final deptCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    DateTime effective = DateTime.now();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setInner) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add Dollar Rate', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: deptCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Department ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Dollar per Point',
                      prefixText: r'$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: effective,
                      );
                      if (picked != null) setInner(() => effective = picked);
                    },
                    icon: const Icon(Icons.event),
                    label: Text('Effective: ${effective.toIso8601String().split('T').first}'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      final deptId = int.tryParse(deptCtrl.text.trim());
                      final rate = double.tryParse(rateCtrl.text.trim());
                      if (deptId == null || rate == null) return;

                      try {
                        await context.read<PayrollViewModel>().createDollarRate(
                              departmentId: deptId,
                              dollarPerPoint: rate,
                              effectiveFrom: effective,
                            );
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to add rate: $e')),
                        );
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    deptCtrl.dispose();
    rateCtrl.dispose();
    if (mounted) _load();
  }
}
