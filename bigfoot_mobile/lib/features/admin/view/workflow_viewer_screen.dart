import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../viewmodel/admin_viewmodel.dart';

class WorkflowViewerScreen extends StatefulWidget {
  const WorkflowViewerScreen({super.key});

  @override
  State<WorkflowViewerScreen> createState() => _WorkflowViewerScreenState();
}

class _WorkflowViewerScreenState extends State<WorkflowViewerScreen> {
  bool _loading = true;
  List<AdminWorkflowTemplate> _templates = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<AdminViewModel>().getWorkflowTemplates();
      if (!mounted) return;
      setState(() => _templates = data);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workflow Templates'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'XP'),
              Tab(text: 'Yeti'),
              Tab(text: 'Deck Over'),
              Tab(text: 'Gooseneck'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
            : TabBarView(
                children: [
                  _series('xp'),
                  _series('yeti'),
                  _series('deck_over'),
                  _series('gooseneck_dump'),
                ],
              ),
      ),
    );
  }

  Widget _series(String series) {
    final rows = _templates.where((e) => e.series == series).toList()
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final t = rows[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.isQcStep ? Colors.green.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.navy,
                child: Text(
                  '${t.stepOrder}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${t.departmentCode} - ${t.departmentName}'),
              ),
              if (t.isQcStep)
                const Chip(
                  label: Text('QC'),
                  backgroundColor: Colors.greenAccent,
                ),
            ],
          ),
        );
      },
    );
  }
}
