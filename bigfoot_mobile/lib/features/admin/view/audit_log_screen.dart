import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../l10n/generated/app_localizations.dart';
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
  final TextEditingController _searchController = TextEditingController();
  /// Debounce timer so typing in the search box doesn't fire a request
  /// per keystroke. Resets every input event; only fires once the user
  /// pauses for ~350ms.
  Timer? _searchDebounce;
  String _search = '';
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
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _search = v.trim();
        _page = 1;
      });
      _load();
    });
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
            q: _search.isEmpty ? null : _search,
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
        _error = AppLocalizations.of(context).auditLogLoadFail('$e');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.auditLogTitle)),
      body: Column(
        children: [
          // Search field above the existing dropdown/userId row. Numeric
          // input is treated as an SO number on the backend (matches every
          // step/QC/delivery row for that trailer); non-numeric matches
          // user.fullName + action verb ILIKE. Debounced so typing doesn't
          // hammer the API.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search SO number, user, or action',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _entityType,
                    decoration: InputDecoration(
                      labelText: l.adminAuditEntityType,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    // Values must match what the audit-log interceptor stores
                    // — see audit-log.interceptor.ts (path → entity_type).
                    items: [
                      DropdownMenuItem(value: null, child: Text(l.customersFilterAll)),
                      DropdownMenuItem(value: 'trailer', child: Text(l.adminAuditEntityTrailer)),
                      DropdownMenuItem(value: 'step', child: Text(l.adminAuditEntityStep)),
                      DropdownMenuItem(value: 'qc_inspection', child: Text(l.adminAuditEntityQcInspection)),
                      DropdownMenuItem(value: 'delivery', child: Text(l.adminAuditEntityDelivery)),
                      DropdownMenuItem(value: 'payroll', child: Text(l.adminAuditEntityPayroll)),
                      DropdownMenuItem(value: 'user', child: Text(l.adminAuditEntityUser)),
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
                    decoration: InputDecoration(
                      labelText: l.adminAuditUserIdLabel,
                      border: const OutlineInputBorder(),
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
                      OutlinedButton(onPressed: _load, child: Text(l.commonRetry)),
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
                  children: [
                    const Icon(Icons.history, size: 48, color: AppColors.disabled),
                    const SizedBox(height: 12),
                    Text(
                      l.adminAuditEmptyMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.disabled),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.adminPullToRefresh,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.disabled, fontSize: 12),
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
                        title: Text(
                          x.entityLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              '${x.actionLabel} · ${x.summary}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${x.userName ?? l.commonUnknown} · ${_fmtTimestamp(x.createdAt)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.disabled,
                              ),
                            ),
                          ],
                        ),
                        childrenPadding: const EdgeInsets.all(12),
                        children: [
                          _kvBlock(l.adminAuditOldValues, x.oldValues),
                          const SizedBox(height: 8),
                          _kvBlock(l.adminAuditNewValues, x.newValues),
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
                  child: Text(l.customersPrev),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(l.customersPageOf(_page, _totalPages)),
                ),
                OutlinedButton(
                  onPressed: _page < _totalPages
                      ? () {
                          setState(() => _page += 1);
                          _load();
                        }
                      : null,
                  child: Text(l.customersNext),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "12:47 PM" for today, "Tue 6:21 PM" for the last 7 days, "2026-06-15
  /// 14:33" for anything older. The relative-time crutch is what makes the
  /// log scannable — admins almost always care about "what happened in the
  /// last few hours" first.
  String _fmtTimestamp(DateTime? ts) {
    if (ts == null) return '-';
    final local = ts.toLocal();
    final now = DateTime.now();
    final today =
        local.year == now.year && local.month == now.month && local.day == now.day;
    final diff = now.difference(local);

    String pad(int n) => n.toString().padLeft(2, '0');
    final time = '${pad(local.hour)}:${pad(local.minute)}';

    if (today) return time;
    if (diff.inDays < 7) {
      const dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${dow[local.weekday - 1]} $time';
    }
    return '${local.year}-${pad(local.month)}-${pad(local.day)} $time';
  }

  /// Renders a JSON-ish map as a key/value table — far easier to read than the
  /// raw JSON dump we used to show, especially when only one field changed.
  /// Falls back to a monospace JSON block for genuinely tabular nested
  /// payloads so the expansion is never empty when the data is non-trivial.
  Widget _kvBlock(String title, Map<String, dynamic>? map) {
    final l = AppLocalizations.of(context);
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
          if (map == null || map.isEmpty)
            Text(l.commonNone,
                style: const TextStyle(color: AppColors.disabled))
          else
            ...map.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: Text(
                          _prettyKey(e.key),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          _prettyValue(e.value),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  static String _prettyKey(String key) {
    // Convert camelCase / snake_case keys to "Sentence case" so the column
    // reads like English, not code.
    final spaced = key
        .replaceAllMapped(
            RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]!.toLowerCase()}')
        .replaceAll('_', ' ');
    return spaced.isEmpty
        ? key
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  static String _prettyValue(dynamic v) {
    if (v == null) return '—';
    if (v is String) return v.isEmpty ? '(empty)' : v;
    if (v is num || v is bool) return v.toString();
    return const JsonEncoder.withIndent('  ').convert(v);
  }
}
