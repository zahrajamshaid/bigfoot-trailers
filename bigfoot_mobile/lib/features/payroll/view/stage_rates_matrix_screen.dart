import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';

/// Editable PAY matrix — flat worker pay per model + department. Owner / office /
/// production_manager can tap any cell to set the pay (blanks included, so new
/// models can be filled in). Cost is not shown here — it lives on Health Check.
class StageRatesMatrixScreen extends StatefulWidget {
  const StageRatesMatrixScreen({super.key});

  @override
  State<StageRatesMatrixScreen> createState() => _StageRatesMatrixScreenState();
}

class _StageRatesMatrixScreenState extends State<StageRatesMatrixScreen> {
  bool _loading = true;
  String? _error;
  List<_Model> _models = [];
  List<_Dept> _depts = [];
  // modelId -> deptId -> cell
  Map<int, Map<int, _Cell>> _byModel = {};
  final _search = TextEditingController();
  String _query = '';

  DioClient get _api => context.read<DioClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.payrollStageRates,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      _apply(resp.data ?? const {});
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _apply(Map<String, dynamic> data) {
    _models = ((data['models'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_Model.fromJson)
        .toList();
    _depts = ((data['departments'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_Dept.fromJson)
        .toList();
    final byModel = <int, Map<int, _Cell>>{};
    for (final c in ((data['cells'] as List<dynamic>?) ?? const [])) {
      if (c is Map<String, dynamic>) {
        final cell = _Cell.fromJson(c);
        byModel.putIfAbsent(cell.modelId, () => {})[cell.deptId] = cell;
      }
    }
    _byModel = byModel;
  }

  Future<void> _editPay(_Model m, _Dept d) async {
    final cell = _byModel[m.id]?[d.id];
    final controller =
        TextEditingController(text: cell != null ? _fmt(cell.pay) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${m.code} · ${d.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Pay (\$)',
            prefixText: '\$ ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v < 0) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      final resp = await _api.patch<Map<String, dynamic>>(
        ApiEndpoints.payrollStageRates,
        data: {'trailerModelId': m.id, 'departmentId': d.id, 'pay': result},
        fromJson: (d2) => d2 as Map<String, dynamic>,
      );
      _apply(resp.data ?? const {});
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final models = _query.isEmpty
        ? _models
        : _models
            .where((m) =>
                m.code.toLowerCase().contains(_query) ||
                m.name.toLowerCase().contains(_query))
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Pay matrix')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? _Retry(message: 'Could not load the pay matrix', onRetry: _load)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _search,
                        onChanged: (v) =>
                            setState(() => _query = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: 'Search model…',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border:
                              OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Tap a stage to set its pay',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.amber,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: models.length,
                          itemBuilder: (context, i) => _modelCard(models[i]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _modelCard(_Model m) {
    final cells = _byModel[m.id] ?? const {};
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(m.code,
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
        subtitle:
            Text(m.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: _depts.map((d) {
          final c = cells[d.id];
          final hasPay = c != null && c.pay > 0;
          return ListTile(
            dense: true,
            onTap: () => _editPay(m, d),
            title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: c?.split != null
                ? Text('crew: ${c!.split!.map((s) => '\$${_fmt(s)}').join(' / ')}',
                    style: const TextStyle(fontSize: 11, color: AppColors.amber))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasPay ? '\$${_fmt(c.pay)}' : 'set',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: hasPay ? AppColors.success : AppColors.disabled,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.edit_outlined, size: 16, color: AppColors.disabled),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _Model {
  final int id;
  final String code;
  final String name;
  _Model({required this.id, required this.code, required this.name});
  factory _Model.fromJson(Map<String, dynamic> j) => _Model(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
      );
}

class _Dept {
  final int id;
  final String code;
  final String name;
  _Dept({required this.id, required this.code, required this.name});
  factory _Dept.fromJson(Map<String, dynamic> j) => _Dept(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
      );
}

class _Cell {
  final int modelId;
  final int deptId;
  final double pay;
  final List<double>? split;
  _Cell({required this.modelId, required this.deptId, required this.pay, this.split});
  factory _Cell.fromJson(Map<String, dynamic> j) => _Cell(
        modelId: (j['modelId'] as num).toInt(),
        deptId: (j['departmentId'] as num).toInt(),
        pay: (j['pay'] as num?)?.toDouble() ?? 0,
        split: (j['split'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

class _Retry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Retry({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
