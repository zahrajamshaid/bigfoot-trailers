import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/models/payroll_adjustment.dart';
import '../../../domain/repositories/payroll_repository.dart';

/// Manual payroll line-items — bonus, correction, or deduction — a manager
/// (owner/office/PM) adds to a worker's pay for a week. Folds into the weekly
/// report total. This is the escape hatch for anything the automatic pay
/// engine can't express (e.g. paying a crew that covered for an absent member).
class PayrollAdjustmentsScreen extends StatefulWidget {
  const PayrollAdjustmentsScreen({super.key});

  @override
  State<PayrollAdjustmentsScreen> createState() =>
      _PayrollAdjustmentsScreenState();
}

class _PayrollAdjustmentsScreenState extends State<PayrollAdjustmentsScreen> {
  late DateTime _weekSunday;
  bool _loading = true;
  String? _error;
  List<PayrollAdjustment> _items = const [];
  List<({int id, String name})> _users = const [];

  DioClient get _api => context.read<DioClient>();
  PayrollRepository get _repo => context.read<PayrollRepository>();

  @override
  void initState() {
    super.initState();
    _weekSunday = _sundayOf(DateTime.now().toUtc());
    _load();
  }

  static DateTime _sundayOf(DateTime d) {
    final utc = DateTime.utc(d.year, d.month, d.day);
    return utc.subtract(Duration(days: utc.weekday % 7)); // Sun=7%7=0
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _weekLabel {
    final end = _weekSunday.add(const Duration(days: 6));
    return '${_weekSunday.month}/${_weekSunday.day} – ${end.month}/${end.day}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final adj = await _repo.getAdjustments(weekStart: _fmt(_weekSunday));
      // Users for the picker (only need the once).
      if (_users.isEmpty) {
        final usersResp = await _api.get<Map<String, dynamic>>(
          ApiEndpoints.users,
          fromJson: (d) => d as Map<String, dynamic>,
        );
        final list = (usersResp.data?['items'] as List<dynamic>?) ??
            (usersResp.data?['users'] as List<dynamic>?) ??
            const [];
        _users = list.whereType<Map<String, dynamic>>().map((j) {
          return (
            id: int.parse(j['id'].toString()),
            name: (j['fullName'] ?? j['name'] ?? j['email'] ?? 'User') as String,
          );
        }).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      if (!mounted) return;
      setState(() {
        _items = adj;
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

  void _shiftWeek(int deltaWeeks) {
    setState(() => _weekSunday =
        _weekSunday.add(Duration(days: 7 * deltaWeeks)));
    _load();
  }

  Future<void> _openEditor([PayrollAdjustment? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AdjustmentEditor(
        users: _users,
        existing: existing,
        weekSunday: _weekSunday,
      ),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _void(PayrollAdjustment a) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove line-item?'),
        content: Text(
            '${a.fullName}: ${_money(a.dollars)} — "${a.note}". This voids it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.voidAdjustment(a.id);
      if (mounted) _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  static String _money(double d) =>
      '${d < 0 ? '-' : ''}\$${d.abs().toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (s, a) => s + a.dollars);
    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Adjustments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _users.isEmpty ? null : () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          // Week navigator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: AppColors.navy.withValues(alpha: 0.06),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftWeek(-1),
                ),
                Expanded(
                  child: Text(
                    'Week of $_weekLabel',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftWeek(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : _items.isEmpty
                        ? const Center(
                            child: Text('No adjustments this week. Tap Add.'))
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: _items.length + 1,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              if (i == _items.length) {
                                return ListTile(
                                  title: const Text('Total',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  trailing: Text(_money(total),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.navy)),
                                );
                              }
                              final a = _items[i];
                              final positive = a.dollars >= 0;
                              return ListTile(
                                leading: Icon(
                                  positive
                                      ? Icons.add_circle_outline
                                      : Icons.remove_circle_outline,
                                  color: positive
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                                title: Text(a.fullName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text('${a.effectiveDate} · ${a.note}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_money(a.dollars),
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: positive
                                                ? AppColors.success
                                                : AppColors.error)),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => _void(a),
                                    ),
                                  ],
                                ),
                                onTap: () => _openEditor(a),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _AdjustmentEditor extends StatefulWidget {
  final List<({int id, String name})> users;
  final PayrollAdjustment? existing;
  final DateTime weekSunday;

  const _AdjustmentEditor({
    required this.users,
    required this.existing,
    required this.weekSunday,
  });

  @override
  State<_AdjustmentEditor> createState() => _AdjustmentEditorState();
}

class _AdjustmentEditorState extends State<_AdjustmentEditor> {
  int? _userId;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _search = TextEditingController();
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _userId = e.userId;
      _amountCtrl.text = e.dollars.toString();
      _noteCtrl.text = e.note;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final note = _noteCtrl.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (!_isEdit && _userId == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Pick a worker.')));
      return;
    }
    if (amount == null || amount == 0) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Enter a non-zero amount.')));
      return;
    }
    if (note.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Add a reason/note.')));
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<PayrollRepository>();
    final navigator = Navigator.of(context);
    try {
      if (_isEdit) {
        await repo.updateAdjustment(
            id: widget.existing!.id, dollars: amount, note: note);
      } else {
        await repo.createAdjustment(
          userId: _userId!,
          effectiveDate:
              _PayrollAdjustmentsScreenState._fmt(widget.weekSunday),
          dollars: amount,
          note: note,
        );
      }
      navigator.pop(true);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.users
        : widget.users
            .where((u) => u.name.toLowerCase().contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Edit adjustment' : 'New adjustment',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (!_isEdit) ...[
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Find worker',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in filtered)
                      RadioListTile<int>(
                        dense: true,
                        value: u.id,
                        groupValue: _userId,
                        onChanged: (v) => setState(() => _userId = v),
                        title: Text(u.name),
                      ),
                  ],
                ),
              ),
              const Divider(),
            ] else
              Text(widget.existing!.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount (\$) — negative for a deduction',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (shown on the payroll line)',
                border: OutlineInputBorder(),
              ),
              maxLength: 200,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Save' : 'Add line-item'),
            ),
          ],
        ),
      ),
    );
  }
}
