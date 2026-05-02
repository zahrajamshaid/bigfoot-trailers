import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../viewmodel/admin_viewmodel.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  bool _loading = true;
  String? _error;
  String? _entityType;
  final TextEditingController _userId = TextEditingController();
  int _page = 1;
  int _totalPages = 1;
  List<AdminAuditLogEntry> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<AdminViewModel>().getAuditLogs(
            entityType: _entityType,
            userId: int.tryParse(_userId.text.trim()),
            page: _page,
            limit: 20,
          );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _totalPages = result.totalPages;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _totalPages = 1;
        _error = 'Failed to load audit log: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Log')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _entityType,
                    decoration: const InputDecoration(
                      labelText: 'Entity Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    // Values must match what the audit-log interceptor stores
                    // — see audit-log.interceptor.ts (path → entity_type).
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All')),
                      DropdownMenuItem(value: 'trailer', child: Text('Trailer')),
                      DropdownMenuItem(value: 'step', child: Text('Production Step')),
                      DropdownMenuItem(value: 'qc_inspection', child: Text('QC Inspection')),
                      DropdownMenuItem(value: 'delivery', child: Text('Delivery')),
                      DropdownMenuItem(value: 'payroll', child: Text('Payroll')),
                      DropdownMenuItem(value: 'user', child: Text('User')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _entityType = v;
                        _page = 1;
                      });
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _userId,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'User ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      setState(() => _page = 1);
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.amber),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppColors.error),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              ),
            )
          else if (_items.isEmpty)
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
                  children: const [
                    Icon(Icons.history, size: 48, color: AppColors.disabled),
                    SizedBox(height: 12),
                    Text(
                      'No audit log entries match these filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.disabled),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Pull down to refresh.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.disabled, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final x = _items[i];
                    return Card(
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        title: Text('${x.action.toUpperCase()} ${x.entityType}#${x.entityId}'),
                        subtitle: Text(
                          '${x.userName ?? 'Unknown'} • ${x.createdAt?.toLocal().toString() ?? '-'}',
                        ),
                        childrenPadding: const EdgeInsets.all(12),
                        children: [
                          _jsonBlock('Old Values', x.oldValues),
                          const SizedBox(height: 8),
                          _jsonBlock('New Values', x.newValues),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _page > 1
                      ? () {
                          setState(() => _page -= 1);
                          _load();
                        }
                      : null,
                  child: const Text('Prev'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Page $_page / $_totalPages'),
                ),
                OutlinedButton(
                  onPressed: _page < _totalPages
                      ? () {
                          setState(() => _page += 1);
                          _load();
                        }
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonBlock(String title, Map<String, dynamic>? map) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectableText(
            map == null ? 'None' : const JsonEncoder.withIndent('  ').convert(map),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}
