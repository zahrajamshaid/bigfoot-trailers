import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../viewmodel/admin_viewmodel.dart';

/// Editable grid where admin assigns an approximate dollar cost to every
/// (trailer model × production department) cell. Drives the Production
/// Report's WIP cost summary — same intent as the payroll point matrix
/// but the values represent material/labour cost rather than points.
class ProductionCostMatrixScreen extends StatefulWidget {
  const ProductionCostMatrixScreen({super.key});

  @override
  State<ProductionCostMatrixScreen> createState() =>
      _ProductionCostMatrixScreenState();
}

class _ProductionCostMatrixScreenState
    extends State<ProductionCostMatrixScreen> {
  bool _loading = true;
  String? _error;
  ProductionCostMatrix? _matrix;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final m =
          await context.read<AdminViewModel>().getProductionCostMatrix();
      if (!mounted) return;
      setState(() {
        _matrix = m;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _editCell(
    ProductionCostModel model,
    ProductionCostDepartment dept,
    double? current,
  ) async {
    final controller = TextEditingController(
      text: current == null ? '' : current.toStringAsFixed(2),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${model.code} · ${dept.code}'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true, signed: false),
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: r'$ ',
            labelText: 'Cost in dollars',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter a non-negative number')),
                );
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (!mounted) return;
    final vm = context.read<AdminViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await vm.upsertProductionCost(
        trailerModelId: model.id,
        departmentId: dept.id,
        costDollars: result,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Production cost matrix')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _matrix == null || _matrix!.models.isEmpty
                  ? const _EmptyView()
                  : _Grid(matrix: _matrix!, onTapCell: _editCell),
    );
  }
}

class _Grid extends StatelessWidget {
  final ProductionCostMatrix matrix;
  final Future<void> Function(
    ProductionCostModel,
    ProductionCostDepartment,
    double?,
  ) onTapCell;

  const _Grid({required this.matrix, required this.onTapCell});

  @override
  Widget build(BuildContext context) {
    // Per-row totals tell admin how much each model is configured to cost
    // through the floor end-to-end — quick sanity check for the matrix.
    double totalFor(ProductionCostModel m) {
      double t = 0;
      for (final d in matrix.departments) {
        t += matrix.costFor(m.id, d.id) ?? 0;
      }
      return t;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            AppColors.navy.withValues(alpha: 0.06),
          ),
          columnSpacing: 18,
          columns: [
            const DataColumn(
              label: Text(
                'Model',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ...matrix.departments.map(
              (d) => DataColumn(
                label: Tooltip(
                  message: d.displayName,
                  child: Text(
                    d.code,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const DataColumn(
              label: Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          rows: matrix.models.map((m) {
            return DataRow(
              cells: [
                DataCell(
                  Tooltip(
                    message: m.displayName,
                    child: Text(
                      m.code,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                ...matrix.departments.map((d) {
                  final v = matrix.costFor(m.id, d.id);
                  return DataCell(
                    Text(v == null ? '—' : _fmt(v)),
                    onTap: () => onTapCell(m, d, v),
                  );
                }),
                DataCell(
                  Text(
                    _fmt(totalFor(m)),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  static String _fmt(double v) {
    if (v == 0) return r'$0';
    // Drop trailing zeros for whole-dollar values so the grid stays compact.
    final s = v.toStringAsFixed(2);
    final trimmed = s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
    return '\$$trimmed';
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No active trailer models yet — add models to populate the matrix.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.disabled),
        ),
      ),
    );
  }
}
