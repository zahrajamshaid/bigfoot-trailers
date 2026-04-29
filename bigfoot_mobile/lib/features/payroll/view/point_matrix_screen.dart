import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
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
    final pointsCtrl = TextEditingController(
      text: existing?.points.toStringAsFixed(2) ?? '',
    );
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
                  const Text('Edit Point Value', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pointsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Points',
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
                      if (picked != null) {
                        setInner(() => effective = picked);
                      }
                    },
                    icon: const Icon(Icons.event),
                    label: Text('Effective: ${effective.toIso8601String().split('T').first}'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      final points = double.tryParse(pointsCtrl.text.trim());
                      if (points == null) return;

                      try {
                        if (existing == null) {
                          await context.read<PayrollViewModel>().createPointValue(
                                trailerModelId: trailerModelId,
                                departmentId: departmentId,
                                points: points,
                                effectiveFrom: effective,
                              );
                        } else {
                          // To support future-dated rates, create a new row when selected date is in the future.
                          if (effective.isAfter(DateTime.now())) {
                            await context.read<PayrollViewModel>().createPointValue(
                                  trailerModelId: trailerModelId,
                                  departmentId: departmentId,
                                  points: points,
                                  effectiveFrom: effective,
                                );
                          } else {
                            await context.read<PayrollViewModel>().updatePointValue(
                                  id: existing.id,
                                  points: points,
                                );
                          }
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save: $e')),
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

    pointsCtrl.dispose();
    if (mounted) _load();
  }
}
