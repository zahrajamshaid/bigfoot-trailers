import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/validation/validators.dart';
import '../../../data/models/payroll_record.dart';
import '../viewmodel/payroll_viewmodel.dart';

class PointMatrixScreen extends StatefulWidget {
  const PointMatrixScreen({super.key});

  @override
  State<PointMatrixScreen> createState() => _PointMatrixScreenState();
}

class _PointMatrixScreenState extends State<PointMatrixScreen> {
  bool _loading = true;
  List<PointValue> _values = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final values = await context.read<PayrollViewModel>().getPointValues();
      if (!mounted) return;
      setState(() => _values = values);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelIds = _values.map((v) => v.trailerModelId).toSet().toList()..sort();
    final deptIds = _values.map((v) => v.departmentId).toSet().toList()..sort();

    final modelById = {
      for (final v in _values)
        if (v.trailerModel != null) v.trailerModelId: v.trailerModel!,
    };
    final deptById = {
      for (final v in _values)
        if (v.department != null) v.departmentId: v.department!,
    };

    PointValue? findCell(int deptId, int modelId) {
      final candidates = _values
          .where((v) => v.departmentId == deptId && v.trailerModelId == modelId)
          .toList()
        ..sort((a, b) => (b.effectiveFrom ?? DateTime(1970))
            .compareTo(a.effectiveFrom ?? DateTime(1970)));
      return candidates.isEmpty ? null : candidates.first;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Point Values Matrix')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.navy.withValues(alpha: 0.08)),
                columns: [
                  const DataColumn(label: Text('Department')),
                  ...modelIds.map((id) => DataColumn(label: Text(modelById[id]?.displayName ?? 'Model $id'))),
                ],
                rows: deptIds.map((deptId) {
                  return DataRow(
                    cells: [
                      DataCell(Text('${deptById[deptId]?.code ?? deptId}')),
                      ...modelIds.map((modelId) {
                        final cell = findCell(deptId, modelId);
                        final hasValue = cell != null;
                        return DataCell(
                          GestureDetector(
                            onTap: () => _editCell(deptId, modelId, cell),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: hasValue
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : AppColors.warning.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(hasValue ? cell.points.toStringAsFixed(2) : '—'),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  Future<void> _editCell(int departmentId, int trailerModelId, PointValue? existing) async {
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
}

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
        SnackBar(content: Text('Failed to save: $e')),
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
            const Text('Edit Point Value',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            TextFormField(
              controller: _pointsCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Points',
                border: OutlineInputBorder(),
              ),
              validator: (v) => Validators.requiredPositiveNumber(v,
                  fieldName: 'a points value'),
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
