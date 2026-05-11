import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/department.dart';
import '../../../data/models/payroll_record.dart';
import '../../admin/viewmodel/admin_viewmodel.dart';
import '../viewmodel/payroll_viewmodel.dart';

class DollarRatesScreen extends StatefulWidget {
  const DollarRatesScreen({super.key});

  @override
  State<DollarRatesScreen> createState() => _DollarRatesScreenState();
}

class _DollarRatesScreenState extends State<DollarRatesScreen> {
  bool _loading = true;
  List<DollarRate> _rates = const [];
  List<Department> _departments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final ratesFuture = context.read<PayrollViewModel>().getDollarRates();
      final deptsFuture = context.read<AdminViewModel>().getDepartments();
      final rates = await ratesFuture;
      final depts = (await deptsFuture) as List<Department>;
      if (!mounted) return;
      setState(() {
        _rates = rates;
        _departments = depts;
      });
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
      list.sort((a, b) => (b.effectiveFrom ?? DateTime(1970))
          .compareTo(a.effectiveFrom ?? DateTime(1970)));
    }

    final deptById = {for (final d in _departments) d.id: d};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dollar Rates'),
        actions: [
          IconButton(onPressed: _openAddSheet, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : RefreshIndicator(
              onRefresh: _load,
              child: grouped.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 80),
                        Center(child: Text('No dollar rates yet. Tap + to add one.')),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: grouped.entries.map((entry) {
                        final latest = entry.value.first;
                        final dept = deptById[entry.key];
                        final deptName = dept?.displayName ??
                            latest.department?.displayName ??
                            'Department ${entry.key}';
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
                                  title: Text(
                                      r'$ ${r.dollarPerPoint.toStringAsFixed(2)} / point'),
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
            ),
    );
  }

  Future<void> _openAddSheet() async {
    if (_departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Departments not loaded yet. Try again.')),
      );
      return;
    }

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddDollarRateSheet(departments: _departments),
    );

    if (created == true && mounted) {
      await _load();
    }
  }
}

class _AddDollarRateSheet extends StatefulWidget {
  final List<Department> departments;

  const _AddDollarRateSheet({required this.departments});

  @override
  State<_AddDollarRateSheet> createState() => _AddDollarRateSheetState();
}

class _AddDollarRateSheetState extends State<_AddDollarRateSheet> {
  final _formKey = GlobalKey<FormState>();
  final _rateCtrl = TextEditingController();
  int? _selectedDeptId;
  DateTime _effective = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _effective,
    );
    if (picked != null && mounted) {
      setState(() => _effective = picked);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final deptId = _selectedDeptId;
    if (deptId == null) return;
    final rate = double.tryParse(_rateCtrl.text.trim());
    if (rate == null) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<PayrollViewModel>().createDollarRate(
            departmentId: deptId,
            dollarPerPoint: rate,
            effectiveFrom: _effective,
          );
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to add rate: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Dollar Rate',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _selectedDeptId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Department',
                border: OutlineInputBorder(),
              ),
              items: widget.departments
                  .map((d) => DropdownMenuItem<int>(
                        value: d.id,
                        child: Text('${d.code} — ${d.displayName}'),
                      ))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _selectedDeptId = v),
              validator: (v) => v == null ? 'Select a department' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _rateCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Dollar per Point',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter a valid positive number';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickDate,
              icon: const Icon(Icons.event),
              label: Text(
                  'Effective: ${_effective.toIso8601String().split('T').first}'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
