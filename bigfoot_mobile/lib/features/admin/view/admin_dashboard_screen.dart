import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/layout/responsive.dart';
import '../../../core/router/route_names.dart';
import '../../../core/websocket/realtime_cubits.dart';
import '../viewmodel/admin_viewmodel.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  AdminDashboardStats? _stats;
  StreamSubscription<RealtimeTick>? _realtimeSub;
  Timer? _realtimeDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeSub = context
        .read<DashboardStatsRealtimeCubit>()
        .stream
        .listen(_onRealtimeTick);
  }

  void _onRealtimeTick(RealtimeTick _) {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final stats = await context.read<AdminViewModel>().getDashboardStats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _realtimeDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats ?? const AdminDashboardStats();
    final r = context.responsive;
    final statCols = r.gridColumns(compact: 2, medium: 4, expanded: 4, large: 4);

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ResponsiveContent(
                padding: EdgeInsets.symmetric(
                  horizontal: r.pagePadding,
                  vertical: 12,
                ),
                child: ListView(
                  children: [
                    GridView.count(
                      crossAxisCount: statCols,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: r.statCardAspectRatio,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        _StatCard(title: 'Total Users', value: '${stats.totalUsers}'),
                        _StatCard(title: 'Active Trailers', value: '${stats.activeTrailers}'),
                        _StatCard(title: 'Weekly Output', value: '${stats.weeklyProduction}'),
                        _StatCard(
                          title: 'QC Fail Rate',
                          value: '${stats.qcFailRate.toStringAsFixed(1)}%',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _NavTile(
                      icon: Icons.people_alt,
                      title: 'User Management',
                      subtitle: 'Create/edit/deactivate users and filter by role',
                      onTap: () => context.pushNamed(RouteNames.userManagement),
                    ),
                    _NavTile(
                      icon: Icons.account_tree,
                      title: 'Department Config',
                      subtitle: 'Edit stall thresholds and inspect workflow mapping',
                      onTap: () => context.pushNamed(RouteNames.departmentConfig),
                    ),
                    _NavTile(
                      icon: Icons.view_timeline,
                      title: 'Workflow Templates',
                      subtitle: 'View 4 trailer series template steps',
                      onTap: () => context.pushNamed(RouteNames.workflowViewer),
                    ),
                    _NavTile(
                      icon: Icons.history,
                      title: 'Audit Log',
                      subtitle: 'Paginated events with before/after changes',
                      onTap: () => context.pushNamed(RouteNames.auditLog),
                    ),
                    _NavTile(
                      icon: Icons.bar_chart,
                      title: 'Production Reports',
                      subtitle: 'Weekly summary and worker output overview',
                      onTap: () => context.pushNamed(RouteNames.adminReports),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;

  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.disabled),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              value,
              key: ValueKey(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.navy),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
