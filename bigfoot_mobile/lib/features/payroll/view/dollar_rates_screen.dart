import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/department.dart';
import '../../../data/models/payroll_record.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../admin/viewmodel/admin_viewmodel.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
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

  Future<void> _confirmDelete(DollarRate rate, String deptName) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.payrollDrDeleteTitle),
        content: Text(l.payrollDrDeleteBody(
            rate.dollarPerPoint.toStringAsFixed(2), deptName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<PayrollViewModel>().deleteDollarRate(rate.id);
      if (mounted) await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.payrollDrDeleteFail('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final auth = context.watch<AuthViewModel>().state;
    final role = auth is Authenticated ? auth.user.role : '';
    final canManage =
        role == UserRole.owner || role == UserRole.productionManager;
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
        title: Text(l.payrollDrTitle),
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
                      children: [
                        const SizedBox(height: 80),
                        Center(child: Text(l.payrollDrEmpty)),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: grouped.entries.map((entry) {
                        final latest = entry.value.first;
                        final dept = deptById[entry.key];
                        final deptName = dept?.displayName ??
                            latest.department?.displayName ??
                            l.payrollDrDeptFallback(entry.key);
                        return Card(
                          child: ExpansionTile(
                            title: Text(deptName),
                            subtitle: Text(l.payrollDrCurrent(
                                latest.dollarPerPoint.toStringAsFixed(2))),
                            children: [
                              ...entry.value.map(
                                (r) => ListTile(
                                  dense: true,
                                  title: Text(l.payrollDrRatePerPoint(
                                      r.dollarPerPoint.toStringAsFixed(2))),
                                  subtitle: Text(l.payrollDrFromTo(
                                      r.effectiveFrom
                                              ?.toIso8601String()
                                              .split('T')
                                              .first ??
                                          '-',
                                      r.effectiveTo
                                              ?.toIso8601String()
                                              .split('T')
                                              .first ??
                                          l.payrollDrPresent)),
                                  trailing: canManage
                                      ? IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: AppColors.error),
                                          tooltip: l.commonDelete,
                                          onPressed: () =>
                                              _confirmDelete(r, deptName),
                                        )
                                      : null,
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
    final l = AppLocalizations.of(context);
    if (_departments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.payrollDrDeptsNotLoaded)),
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
    final l = AppLocalizations.of(context);
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
        SnackBar(content: Text(l.payrollDrAddFail('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
            Text(
              l.payrollDrAddTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _selectedDeptId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.payrollPmDept,
                border: const OutlineInputBorder(),
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
              validator: (v) => v == null ? l.payrollPmSelectDept : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _rateCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l.payrollDrDollarLabel,
                prefixText: r'$ ',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return l.payrollDrValidNumber;
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickDate,
              icon: const Icon(Icons.event),
              label: Text(l.payrollPmEffective(
                  _effective.toIso8601String().split('T').first)),
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
                  : Text(l.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}
