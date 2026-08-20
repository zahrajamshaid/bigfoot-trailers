import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/user_activity.dart';
import '../../../domain/repositories/activity_repository.dart';

/// Admin (owner/office) view of who's using the app and for how long.
/// Pick a range → per-user days-active + time-on-app, busiest first. Tap a
/// user for their day-by-day breakdown.
class UserActivityScreen extends StatefulWidget {
  const UserActivityScreen({super.key});

  @override
  State<UserActivityScreen> createState() => _UserActivityScreenState();
}

enum _Range { today, week, month }

class _UserActivityScreenState extends State<UserActivityScreen> {
  _Range _range = _Range.week;
  bool _loading = true;
  String? _error;
  UserActivitySummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({String from, String to}) _rangeDates() {
    final today = DateTime.now().toUtc();
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final to = DateTime.utc(today.year, today.month, today.day);
    final from = switch (_range) {
      _Range.today => to,
      _Range.week => to.subtract(const Duration(days: 6)),
      _Range.month => to.subtract(const Duration(days: 29)),
    };
    return (from: fmt(from), to: fmt(to));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = _rangeDates();
      final summary = await context
          .read<ActivityRepository>()
          .getSummary(from: r.from, to: r.to);
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  void _setRange(_Range r) {
    if (r == _range) return;
    setState(() => _range = r);
    _load();
  }

  Future<void> _openUser(UserActivityRow row) async {
    final r = _rangeDates();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _UserDailySheet(row: row, from: r.from, to: r.to),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _summary?.users ?? const [];
    final totalSeconds =
        users.fold<int>(0, (s, u) => s + u.totalActiveSeconds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Activity'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<_Range>(
              segments: const [
                ButtonSegment(value: _Range.today, label: Text('Today')),
                ButtonSegment(value: _Range.week, label: Text('7 days')),
                ButtonSegment(value: _Range.month, label: Text('30 days')),
              ],
              selected: {_range},
              onSelectionChanged: (s) => _setRange(s.first),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Error(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _SummaryHeader(
                        activeUsers: users.length,
                        totalSeconds: totalSeconds,
                        from: _summary?.from ?? '',
                        to: _summary?.to ?? '',
                      ),
                      const SizedBox(height: 8),
                      if (users.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('No app usage recorded in this range.'),
                          ),
                        ),
                      for (final u in users)
                        _UserRow(row: u, onTap: () => _openUser(u)),
                    ],
                  ),
                ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final int activeUsers;
  final int totalSeconds;
  final String from;
  final String to;

  const _SummaryHeader({
    required this.activeUsers,
    required this.totalSeconds,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$activeUsers',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
                const Text('active users', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatActiveDuration(totalSeconds),
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy)),
                const Text('total time on app',
                    style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (from.isNotEmpty)
            Text('$from\n→ $to',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final UserActivityRow row;
  final VoidCallback onTap;

  const _UserRow({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.navy.withValues(alpha: 0.12),
          child: Text(
            row.fullName.isNotEmpty ? row.fullName[0].toUpperCase() : '?',
            style: const TextStyle(
                color: AppColors.navy, fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(row.fullName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${row.role ?? '—'} · ${row.daysActive} day${row.daysActive == 1 ? '' : 's'} active'
          '${row.lastSeenAt != null ? ' · last seen ${_shortWhen(row.lastSeenAt!)}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatActiveDuration(row.totalActiveSeconds),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.navy)),
            const Text('on app', style: TextStyle(fontSize: 10)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _UserDailySheet extends StatefulWidget {
  final UserActivityRow row;
  final String from;
  final String to;

  const _UserDailySheet({
    required this.row,
    required this.from,
    required this.to,
  });

  @override
  State<_UserDailySheet> createState() => _UserDailySheetState();
}

class _UserDailySheetState extends State<_UserDailySheet> {
  bool _loading = true;
  String? _error;
  UserDailyActivity? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<ActivityRepository>().getUserDaily(
            widget.row.userId,
            from: widget.from,
            to: widget.to,
          );
      if (!mounted) return;
      setState(() {
        _data = d;
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

  @override
  Widget build(BuildContext context) {
    final days = _data?.days ?? const [];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.row.fullName,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${widget.row.role ?? '—'} · daily usage',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              )
            else if (days.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No usage in this range.'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: days.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = days[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppColors.navy),
                      title: Text(d.day,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        d.firstSeenAt != null && d.lastSeenAt != null
                            ? '${_hm(d.firstSeenAt!)} – ${_hm(d.lastSeenAt!)}'
                            : '',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(formatActiveDuration(d.activeSeconds),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _hm(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final ap = l.hour < 12 ? 'a' : 'p';
  return '$h:${l.minute.toString().padLeft(2, '0')}$ap';
}

String _shortWhen(DateTime dt) {
  final l = dt.toLocal();
  return '${l.month}/${l.day} ${_hm(dt)}';
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _Error({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
