import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/websocket/ws_client.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pinEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPinSetting();
  }

  Future<void> _loadPinSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _pinEnabled = prefs.getBool('pin_lock_enabled') ?? false);
    }
  }

  Future<void> _togglePin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pin_lock_enabled', value);
    if (mounted) setState(() => _pinEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthViewModel, AuthState>(
      builder: (context, authState) {
        final user = authState is Authenticated ? authState.user : null;

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ── User profile card ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.navy,
                        child: Text(
                          (user?.name.isNotEmpty == true)
                              ? user!.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? 'Unknown',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.disabled),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(
                          (user?.role ?? '')
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                        backgroundColor: AppColors.navy,
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Connection status ─────────────────────────────────────────
            _SectionHeader(title: 'CONNECTION'),
            StreamBuilder<WsConnectionState>(
              stream: context.read<AuthViewModel>().state is Authenticated
                  ? null
                  : null,
              builder: (context, snapshot) {
                return _SettingsTile(
                  icon: Icons.wifi,
                  iconColor: AppColors.success,
                  title: 'WebSocket Status',
                  subtitle: 'Real-time connection',
                  trailing: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),

            // ── Security ──────────────────────────────────────────────────
            _SectionHeader(title: 'SECURITY'),
            _SettingsTile(
              icon: Icons.pin_outlined,
              iconColor: AppColors.navy,
              title: 'Require PIN on App Open',
              subtitle: _pinEnabled ? 'PIN lock is enabled' : 'No PIN required',
              trailing: Switch.adaptive(
                value: _pinEnabled,
                activeColor: AppColors.amber,
                onChanged: _togglePin,
              ),
            ),

            const SizedBox(height: 8),

            // ── About ─────────────────────────────────────────────────────
            _SectionHeader(title: 'ABOUT'),
            _SettingsTile(
              icon: Icons.info_outline,
              iconColor: AppColors.navy,
              title: 'App Version',
              subtitle: 'v1.0.0 (build 1)',
            ),
            _SettingsTile(
              icon: Icons.api,
              iconColor: AppColors.navy,
              title: 'API Version',
              subtitle: 'v1.3',
            ),

            const SizedBox(height: 16),

            // ── Sign out ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout, size: 20),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
            'Are you sure you want to sign out? You will need to sign in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthViewModel>().logout();
      if (context.mounted) context.go('/login');
    }
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.disabled,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.disabled)),
      trailing: trailing,
    );
  }
}
