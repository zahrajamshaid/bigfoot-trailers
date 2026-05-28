import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/validation/validators.dart';
import '../../../data/models/department.dart';
import '../../../data/models/payroll_record.dart';
import '../../../data/models/trailer.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../admin/viewmodel/admin_viewmodel.dart';
import '../viewmodel/payroll_viewmodel.dart';

class PointMatrixScreen extends StatefulWidget {
  const PointMatrixScreen({super.key});

  @override
  State<PointMatrixScreen> createState() => _PointMatrixScreenState();
}

class _PointMatrixScreenState extends State<PointMatrixScreen> {
  bool _loading = true;
  String? _error;
  List<PointValue> _values = const [];
  List<Department> _departments = const [];
  List<TrailerModelInfo> _models = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Production (non-QC) departments only — QC departments do not award points.
  List<Department> get _productionDepartments =>
      _departments.where((d) => !d.isQcStep).toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final payroll = context.read<PayrollViewModel>();
      final admin = context.read<AdminViewModel>();

      final valuesFuture = payroll.getPointValues();
      final deptsFuture = admin.getDepartments();
      final modelsFuture = admin.getTrailerModels();

      final values = await valuesFuture;
      final depts = (await deptsFuture) as List<Department>;
      final models = await modelsFuture;

      if (!mounted) return;
      setState(() {
        _values = values;
        _departments = depts;
        _models = models;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final depts = _productionDepartments;
    final models = [..._models]..sort((a, b) {
        final s = a.series.compareTo(b.series);
        return s != 0 ? s : a.id.compareTo(b.id);
      });

    /// Most recent point value for a (department, model) pair.
    PointValue? findCell(int deptId, int modelId) {
      final candidates = _values
          .where((v) => v.departmentId == deptId && v.trailerModelId == modelId)
          .toList()
        ..sort((a, b) => (b.effectiveFrom ?? DateTime(1970))
            .compareTo(a.effectiveFrom ?? DateTime(1970)));
      return candidates.isEmpty ? null : candidates.first;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.payrollPmTitle),
        actions: [
          IconButton(
            tooltip: l.payrollPmAddTooltip,
            onPressed: _loading ? null : _openAddSheet,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : (depts.isEmpty || models.isEmpty)
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 80),
                          Center(
                            child: Text(
                              l.payrollPmNoData,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8, left: 4),
                                child: Text(
                                  l.payrollPmTapCell,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.disabled,
                                  ),
                                ),
                              ),
                              DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                    AppColors.navy.withValues(alpha: 0.08)),
                                columns: [
                                  DataColumn(label: Text(l.payrollPmDept)),
                                  ...models.map((m) => DataColumn(
                                        label: Text(m.displayName),
                                      )),
                                ],
                                rows: depts.map((dept) {
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(dept.code)),
                                      ...models.map((model) {
                                        final cell =
                                            findCell(dept.id, model.id);
                                        final hasValue = cell != null;
                                        return DataCell(
                                          GestureDetector(
                                            onTap: () => _editCell(
                                                dept.id, model.id, cell),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: hasValue
                                                    ? AppColors.success
                                                        .withValues(alpha: 0.15)
                                                    : AppColors.warning
                                                        .withValues(alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(hasValue
                                                  ? cell.points
                                                      .toStringAsFixed(2)
                                                  : '—'),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
    );
  }

  Future<void> _editCell(
      int departmentId, int trailerModelId, PointValue? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditPointValueSheet(
        departmentId: departmentId,
        trailerModelId: trailerModelId,
        existing: existing,
      ),
    );

    if (saved == true && mounted) await _load();
  }

  Future<void> _openAddSheet() async {
    final l = AppLocalizations.of(context);
    final depts = _productionDepartments;
    if (depts.isEmpty || _models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.payrollPmNotLoaded)),
      );
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPointValueSheet(
        departments: depts,
        models: _models,
      ),
    );

    if (saved == true && mounted) await _load();
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
              l.payrollPmLoadFail(message),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(l.commonRetry)),
          ],
        ),
      ),
    );
  }
}

/// Add a point value by picking a department + trailer model from dropdowns.
class _AddPointValueSheet extends StatefulWidget {
  final List<Department> departments;
  final List<TrailerModelInfo> models;

  const _AddPointValueSheet({required this.departments, required this.models});

  @override
  State<_AddPointValueSheet> createState() => _AddPointValueSheetState();
}

class _AddPointValueSheetState extends State<_AddPointValueSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pointsCtrl = TextEditingController();
  int? _selectedDeptId;
  int? _selectedModelId;
  DateTime _effective = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _pointsCtrl.dispose();
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
    final modelId = _selectedModelId;
    if (deptId == null || modelId == null) return;
    final points = double.tryParse(_pointsCtrl.text.trim());
    if (points == null) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<PayrollViewModel>().createPointValue(
            trailerModelId: modelId,
            departmentId: deptId,
            points: points,
            effectiveFrom: _effective,
          );
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l.payrollPmAddFail('$e'))),
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
            Text(l.payrollPmAddTitle,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
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
            DropdownButtonFormField<int>(
              value: _selectedModelId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.payrollPmTrailerModel,
                border: const OutlineInputBorder(),
              ),
              items: widget.models
                  .map((m) => DropdownMenuItem<int>(
                        value: m.id,
                        child: Text('${m.displayName} (${m.series})'),
                      ))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _selectedModelId = v),
              validator: (v) => v == null ? l.payrollPmSelectModel : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pointsCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l.payrollPmPointsLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => Validators.requiredPositiveNumber(v,
                  fieldName: 'a points value'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickDate,
              icon: const Icon(Icons.event),
              label: Text(l.payrollPmEffective(
                  _effective.toIso8601String().split('T').first)),
            ),
            const SizedBox(height: 12),
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

/// Edit (or create) the point value for a specific cell in the matrix.
class _EditPointValueSheet extends StatefulWidget {
  final int departmentId;
  final int trailerModelId;
  final PointValue? existing;

  const _EditPointValueSheet({
    required this.departmentId,
    required this.trailerModelId,
    required this.existing,
  });

  @override
  State<_EditPointValueSheet> createState() => _EditPointValueSheetState();
}

class _EditPointValueSheetState extends State<_EditPointValueSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pointsCtrl;
  DateTime _effective = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pointsCtrl = TextEditingController(
      text: widget.existing?.points.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _pointsCtrl.dispose();
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
    final points = double.tryParse(_pointsCtrl.text.trim());
    if (points == null) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final vm = context.read<PayrollViewModel>();
    try {
      final existing = widget.existing;
      if (existing == null) {
        await vm.createPointValue(
          trailerModelId: widget.trailerModelId,
          departmentId: widget.departmentId,
          points: points,
          effectiveFrom: _effective,
        );
      } else if (_effective.isAfter(DateTime.now())) {
        // Future-dated change: create a new row so history is preserved.
        await vm.createPointValue(
          trailerModelId: widget.trailerModelId,
          departmentId: widget.departmentId,
          points: points,
          effectiveFrom: _effective,
        );
      } else {
        await vm.updatePointValue(id: existing.id, points: points);
      }
      if (!mounted) return;
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l.payrollPmSaveFail('$e'))),
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
                widget.existing == null
                    ? l.payrollPmSetTitle
                    : l.payrollPmEditTitle,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pointsCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: l.payrollPmPointsLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => Validators.requiredPositiveNumber(v,
                  fieldName: 'a points value'),
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
