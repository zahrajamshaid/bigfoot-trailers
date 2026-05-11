import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/validation/validators.dart';
import '../../../data/models/department.dart';
import '../viewmodel/admin_viewmodel.dart';

class DepartmentConfigScreen extends StatefulWidget {
  const DepartmentConfigScreen({super.key});

  @override
  State<DepartmentConfigScreen> createState() => _DepartmentConfigScreenState();
}

class _DepartmentConfigScreenState extends State<DepartmentConfigScreen> {
  bool _loading = true;
  List<Department> _departments = const [];
  List<AdminWorkflowTemplate> _templates = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final deptFuture = context.read<AdminViewModel>().getDepartments();
      final wfFuture = context.read<AdminViewModel>().getWorkflowTemplates();
      final departments = await deptFuture;
      final templates = await wfFuture;
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _templates = templates;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Department Configuration')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  ..._departments.map(
                    (d) => Card(
                      child: ListTile(
                        title: Text('${d.code} - ${d.displayName}'),
                        subtitle: Text(
                          '${d.isQcStep ? 'QC' : 'Production'} • ${d.completionType} • Stall ${d.stallThresholdHours}h',
                        ),
                        trailing: OutlinedButton(
                          onPressed: () => _editThreshold(d),
                          child: const Text('Edit Threshold'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Workflow Diagram by Series',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...['xp', 'yeti', 'deck_over', 'gooseneck_dump'].map(
                    (series) => _SeriesFlowCard(
                      title: _seriesTitle(series),
                      templates: _templates.where((t) => t.series == series).toList()
                        ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _editThreshold(Department d) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _EditThresholdDialog(department: d),
    );

    if (value == null) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AdminViewModel>().updateDepartmentThreshold(
            id: d.id,
            stallThresholdHours: value,
          );
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update threshold: $e')),
      );
    }
  }

  String _seriesTitle(String series) {
    switch (series) {
      case 'xp':
        return 'XP';
      case 'yeti':
        return 'Yeti';
      case 'deck_over':
        return 'Deck Over';
      case 'gooseneck_dump':
        return 'Gooseneck';
      default:
        return series;
    }
  }
}

class _EditThresholdDialog extends StatefulWidget {
  final Department department;

  const _EditThresholdDialog({required this.department});

  @override
  State<_EditThresholdDialog> createState() => _EditThresholdDialogState();
}

class _EditThresholdDialogState extends State<_EditThresholdDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.department.stallThresholdHours.toString(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final value = int.tryParse(_ctrl.text.trim());
    if (value == null) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.department.code} Stall Threshold'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Hours',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              Validators.requiredPositiveInt(v, fieldName: 'a number of hours'),
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SeriesFlowCard extends StatelessWidget {
  final String title;
  final List<AdminWorkflowTemplate> templates;

  const _SeriesFlowCard({required this.title, required this.templates});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: templates.map((t) {
                final color = t.isQcStep ? Colors.green.shade100 : Colors.blue.shade100;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text('${t.stepOrder}. ${t.departmentCode}'),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
