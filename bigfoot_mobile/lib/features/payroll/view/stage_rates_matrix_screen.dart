import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';

/// Read-only pay + cost matrix, per model + department, straight from the
/// stage-rate table that drives both payroll and WIP cost. Grouped by model.
class StageRatesMatrixScreen extends StatefulWidget {
  const StageRatesMatrixScreen({super.key});

  @override
  State<StageRatesMatrixScreen> createState() => _StageRatesMatrixScreenState();
}

class _StageRatesMatrixScreenState extends State<StageRatesMatrixScreen> {
  bool _loading = true;
  String? _error;
  List<_Model> _models = [];
  Map<int, String> _deptName = {};
  // modelId -> deptId -> cell
  Map<int, Map<int, _Cell>> _byModel = {};
  final _search = TextEditingController();
  String _query = '';

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
      final resp = await context.read<DioClient>().get<Map<String, dynamic>>(
            ApiEndpoints.payrollStageRates,
            fromJson: (d) => d as Map<String, dynamic>,
          );
      final data = resp.data ?? const {};
      final models = ((data['models'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_Model.fromJson)
          .toList();
      final deptName = <int, String>{};
      for (final d in ((data['departments'] as List<dynamic>?) ?? const [])) {
        if (d is Map<String, dynamic>) {
          deptName[(d['id'] as num).toInt()] = d['name'] as String? ?? '';
        }
      }
      final byModel = <int, Map<int, _Cell>>{};
      for (final c in ((data['cells'] as List<dynamic>?) ?? const [])) {
        if (c is Map<String, dynamic>) {
          final cell = _Cell.fromJson(c);
          byModel.putIfAbsent(cell.modelId, () => {})[cell.deptId] = cell;
        }
      }
      if (mounted) {
        setState(() {
          _models = models;
          _deptName = deptName;
          _byModel = byModel;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
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
      appBar: AppBar(title: const Text('Pay & cost matrix')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? _Retry(message: 'Could not load the matrix', onRetry: _load)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          hintText: 'Search model…',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
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
    final sortedDeptIds = cells.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(m.code,
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
        subtitle: Text(m.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Row(
            children: [
              const Expanded(flex: 3, child: Text('Stage', style: _hStyle)),
              const Expanded(flex: 2, child: Text('Pay', style: _hStyle, textAlign: TextAlign.right)),
              const Expanded(flex: 2, child: Text('Cost', style: _hStyle, textAlign: TextAlign.right)),
            ],
          ),
          const Divider(),
          ...sortedDeptIds.map((deptId) {
            final c = cells[deptId]!;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_deptName[deptId] ?? '#$deptId',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (c.split != null)
                          Text('crew: ${c.split!.map((s) => '\$${_fmt(s)}').join(' / ')}',
                              style: TextStyle(fontSize: 11, color: AppColors.amber)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(c.pay > 0 ? '\$${_fmt(c.pay)}' : '—',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('\$${_fmt(c.cost)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: AppColors.navy)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static const _hStyle =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey);

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

class _Cell {
  final int modelId;
  final int deptId;
  final double cost;
  final double pay;
  final List<double>? split;
  _Cell({required this.modelId, required this.deptId, required this.cost, required this.pay, this.split});
  factory _Cell.fromJson(Map<String, dynamic> j) => _Cell(
        modelId: (j['modelId'] as num).toInt(),
        deptId: (j['departmentId'] as num).toInt(),
        cost: (j['cost'] as num?)?.toDouble() ?? 0,
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
