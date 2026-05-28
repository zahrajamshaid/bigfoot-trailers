import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/i18n/locale_cubit.dart';
import '../../../core/security/pin_storage.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PinStorage _pinStorage = PinStorage();
  bool _pinEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPinSetting();
  }

  Future<void> _loadPinSetting() async {
    final enabled = await _pinStorage.isEnabled();
    if (mounted) {
      setState(() => _pinEnabled = enabled);
    }
  }

  Future<void> _togglePin(bool value) async {
    if (value) {
      await _enablePinFlow();
    } else {
      await _disablePinFlow();
    }
  }

  Future<void> _enablePinFlow() async {
    final l = AppLocalizations.of(context);
    // Step 1: collect new PIN.
    final pin = await _promptForPin(
      title: l.settingsPinSetTitle,
      subtitle: l.settingsPinSetSubtitle,
    );
    if (pin == null) return;

    if (!mounted) return;
    // Step 2: confirm by re-entering.
    final confirm = await _promptForPin(
      title: l.settingsPinConfirmTitle,
      subtitle: l.settingsPinConfirmSubtitle,
    );
    if (confirm == null) return;

    if (pin != confirm) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l.settingsPinMismatch)),
        );
      return;
    }

    await _pinStorage.setPin(pin);
    if (mounted) setState(() => _pinEnabled = true);
  }

  Future<void> _disablePinFlow() async {
    final l = AppLocalizations.of(context);
    final pin = await _promptForPin(
      title: l.settingsPinDisableTitle,
      subtitle: l.settingsPinDisableSubtitle,
    );
    if (pin == null) return;
    final ok = await _pinStorage.verify(pin);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l.authPinIncorrect)));
      return;
    }
    await _pinStorage.disable();
    if (mounted) setState(() => _pinEnabled = false);
  }

  Future<String?> _promptForPin({
    required String title,
    required String subtitle,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PinPromptDialog(title: title, subtitle: subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                              user?.name ?? l.commonUnknown,
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
            _SectionHeader(title: l.settingsConnectionSection),
            StreamBuilder<WsConnectionState>(
              stream: context.read<AuthViewModel>().state is Authenticated
                  ? null
                  : null,
              builder: (context, snapshot) {
                return _SettingsTile(
                  icon: Icons.wifi,
                  iconColor: AppColors.success,
                  title: l.settingsWebSocketStatus,
                  subtitle: l.settingsWebSocketSubtitle,
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

            // ── Language ──────────────────────────────────────────────────
            _SectionHeader(title: l.settingsLanguageSection),
            BlocBuilder<LocaleCubit, Locale>(
              builder: (context, locale) {
                final isSpanish = locale.languageCode == 'es';
                return _SettingsTile(
                  icon: Icons.language,
                  iconColor: AppColors.navy,
                  title: l.settingsLanguageTitle,
                  subtitle: isSpanish
                      ? l.settingsLanguageSpanish
                      : l.settingsLanguageEnglish,
                  trailing: Switch.adaptive(
                    value: isSpanish,
                    activeColor: AppColors.amber,
                    onChanged: (_) =>
                        context.read<LocaleCubit>().toggle(),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),

            // ── Security ──────────────────────────────────────────────────
            _SectionHeader(title: l.settingsSecuritySection),
            _SettingsTile(
              icon: Icons.pin_outlined,
              iconColor: AppColors.navy,
              title: l.settingsPinTitle,
              subtitle:
                  _pinEnabled ? l.settingsPinEnabled : l.settingsPinDisabled,
              trailing: Switch.adaptive(
                value: _pinEnabled,
                activeColor: AppColors.amber,
                onChanged: _togglePin,
              ),
            ),

            const SizedBox(height: 8),

            // ── About ─────────────────────────────────────────────────────
            _SectionHeader(title: l.settingsAboutSection),
            _SettingsTile(
              icon: Icons.info_outline,
              iconColor: AppColors.navy,
              title: l.settingsAppVersion,
              subtitle: 'v1.0.0 (build 1)',
            ),
            _SettingsTile(
              icon: Icons.api,
              iconColor: AppColors.navy,
              title: l.settingsApiVersion,
              subtitle: 'v1.3',
            ),

            const SizedBox(height: 16),

            // ── Sign out ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout, size: 20),
                label: Text(l.settingsSignOut),
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
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsSignOutConfirmTitle),
        content: Text(l.settingsSignOutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l.settingsSignOut),
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

// ── PIN prompt dialog ────────────────────────────────────────────────────────

/// Modal dialog that collects exactly 4 digits and pops with the entered
/// string, or null if the user cancels.
class _PinPromptDialog extends StatefulWidget {
  final String title;
  final String subtitle;

  const _PinPromptDialog({required this.title, required this.subtitle});

  @override
  State<_PinPromptDialog> createState() => _PinPromptDialogState();
}

class _PinPromptDialogState extends State<_PinPromptDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.length == 4) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 16),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onChanged: _onChanged,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.settingsPinCancel),
        ),
      ],
    );
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
