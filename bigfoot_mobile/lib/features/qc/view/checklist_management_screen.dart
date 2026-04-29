import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../data/models/qc_inspection.dart';
import '../../../data/models/department.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../viewmodel/qc_viewmodel.dart';

/// Admin screen to manage QC checklist items grouped by QC department.
class ChecklistManagementScreen extends StatefulWidget {
  const ChecklistManagementScreen({super.key});

  @override
  State<ChecklistManagementScreen> createState() => _ChecklistManagementScreenState();
}

class _ChecklistManagementScreenState extends State<ChecklistManagementScreen> {
  late final QcViewModel _cubit;
  List<QcChecklistItem> _items = [];
  List<Department> _qcDepts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cubit = QcViewModel(repository: context.read<QcRepository>(), ws: context.read<WsClient>());
    _load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final api = context.read<DioClient>();
      final items = await _cubit.fetchAllChecklistItems();
      // Load QC departments
      final deptResp = await api.get<List<dynamic>>(
        ApiEndpoints.adminDepartments,
        fromJson: (d) => d as List<dynamic>,
      );
      final qcDepts = (deptResp.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Department.fromJson)
          .where((d) => d.isQcStep)
          .toList();

      if (mounted) {
        setState(() {
          _items = items;
          _qcDepts = qcDepts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = 'Failed to load checklist items'; });
    }
  }

  void _showAddDialog() {
    final labelCtrl = TextEditingController();
    final sortCtrl = TextEditingController(text: '0');
    int? selectedDeptId;
    String selectedSeries = 'all';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Checklist Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: 'QC Department'),
                  items: _qcDepts.map((d) => DropdownMenuItem(
                    value: d.id,
                    child: Text(d.displayName),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedDeptId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sortCtrl,
                  decoration: const InputDecoration(labelText: 'Sort Order'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedSeries,
                  decoration: const InputDecoration(labelText: 'Applies To Series'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Series')),
                    DropdownMenuItem(value: 'xp', child: Text('XP')),
                    DropdownMenuItem(value: 'yeti', child: Text('Yeti')),
                    DropdownMenuItem(value: 'deck_over', child: Text('Deck Over')),
                    DropdownMenuItem(value: 'gooseneck_dump', child: Text('Gooseneck')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedSeries = v ?? 'all'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (selectedDeptId == null || labelCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await _cubit.createChecklistItem(
                    departmentId: selectedDeptId!,
                    label: labelCtrl.text.trim(),
                    sortOrder: int.tryParse(sortCtrl.text) ?? 0,
                    appliesToSeries: selectedSeries,
                  );
                  _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to create: $e')),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(QcChecklistItem item) {
    final labelCtrl = TextEditingController(text: item.label);
    final sortCtrl = TextEditingController(text: '${item.sortOrder}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Checklist Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sortCtrl,
              decoration: const InputDecoration(labelText: 'Sort Order'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _cubit.updateChecklistItem(item.id, isActive: false);
                _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            child: const Text('Deactivate', style: TextStyle(color: AppColors.error)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _cubit.updateChecklistItem(
                  item.id,
                  label: labelCtrl.text.trim(),
                  sortOrder: int.tryParse(sortCtrl.text),
                );
                _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QC Checklist Items'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('No checklist items'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _buildGroupedList(),
                    ),
    );
  }

  Widget _buildGroupedList() {
    // Group items by department
    final grouped = <int, List<QcChecklistItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.departmentId, () => []).add(item);
    }

    final deptIds = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: deptIds.length,
      itemBuilder: (context, index) {
        final deptId = deptIds[index];
        final items = grouped[deptId]!;
        final deptName = _qcDepts
            .where((d) => d.id == deptId)
            .map((d) => d.displayName)
            .firstOrNull ?? 'Dept $deptId';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(
                deptName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
            ...items.map((item) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: item.isActive
                      ? AppColors.navy.withValues(alpha: 0.1)
                      : Colors.grey.shade200,
                  child: Text(
                    '${item.sortOrder}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: item.isActive ? AppColors.navy : Colors.grey,
                    ),
                  ),
                ),
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: item.isActive ? null : TextDecoration.lineThrough,
                    color: item.isActive ? null : Colors.grey,
                  ),
                ),
                subtitle: Text(
                  'Series: ${item.appliesToSeries}${item.isActive ? '' : ' (inactive)'}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _showEditDialog(item),
              ),
            )),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}
