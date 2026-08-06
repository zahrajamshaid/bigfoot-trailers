import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/announcement.dart';
import '../../../domain/repositories/announcement_repository.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Owner / production-manager screen for posting and managing the
/// floor-wide messages that pop up in every user's app shell.
class AnnouncementsAdminScreen extends StatefulWidget {
  const AnnouncementsAdminScreen({super.key});

  @override
  State<AnnouncementsAdminScreen> createState() =>
      _AnnouncementsAdminScreenState();
}

class _AnnouncementsAdminScreenState extends State<AnnouncementsAdminScreen> {
  bool _loading = true;
  String? _error;
  List<AnnouncementWithStats> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items =
          await context.read<AnnouncementRepository>().getAllForAdmin();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _openCreate() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AnnouncementForm(),
    );
    if (result == true && mounted) _load();
  }

  Future<void> _toggleActive(AnnouncementWithStats item) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AnnouncementRepository>().update(
            id: item.announcement.id,
            isActive: !item.isActive,
          );
      if (mounted) _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(AnnouncementWithStats item) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.announcementsDeleteTitle),
        content: Text(l.announcementsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<AnnouncementRepository>()
          .remove(item.announcement.id);
      if (mounted) _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.announcementsTitle),
        actions: [
          IconButton(
            onPressed: _openCreate,
            tooltip: l.announcementsNew,
            icon: const Icon(Icons.campaign),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.campaign_outlined,
                              size: 64, color: AppColors.disabled),
                          const SizedBox(height: 12),
                          Text(l.announcementsEmpty),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _openCreate,
                            icon: const Icon(Icons.add),
                            label: Text(l.announcementsNew),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => _Card(
                          item: _items[i],
                          onToggle: () => _toggleActive(_items[i]),
                          onDelete: () => _delete(_items[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _Card extends StatelessWidget {
  final AnnouncementWithStats item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _Card({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final a = item.announcement;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.title?.isNotEmpty == true
                        ? a.title!
                        : l.announcementDefaultTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.repeat,
                      size: 14, color: Colors.grey.shade700),
                  backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                  label: Text(
                    AnnouncementFrequency.label(a.frequency),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 4),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: item.isActive
                      ? AppColors.success.withValues(alpha: 0.15)
                      : Colors.grey.shade300,
                  label: Text(
                    item.isActive
                        ? l.announcementsActive
                        : l.announcementsInactive,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(a.body, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: AppColors.navy),
                const SizedBox(width: 4),
                Text(
                  l.announcementsAckProgress(item.ackCount, item.totalUsers),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onToggle,
                  icon: Icon(
                    item.isActive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                  ),
                  label: Text(item.isActive
                      ? l.announcementsDeactivate
                      : l.announcementsActivate),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: AppColors.error),
                  label: Text(
                    l.commonDelete,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementForm extends StatefulWidget {
  const _AnnouncementForm();

  @override
  State<_AnnouncementForm> createState() => _AnnouncementFormState();
}

class _AnnouncementFormState extends State<_AnnouncementForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _frequency = AnnouncementFrequency.once;
  DateTime? _expiresAt;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  static String _frequencyHint(String f) {
    switch (f) {
      case AnnouncementFrequency.everyLogin:
        return 'Pops up every time the user opens the app.';
      case AnnouncementFrequency.daily:
        return 'Pops up once a day until it expires.';
      case AnnouncementFrequency.weekly:
        return 'Pops up once a week until it expires.';
      case AnnouncementFrequency.once:
      default:
        return 'Shows until the user taps OK, then never again.';
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked != null) {
      setState(() => _expiresAt = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AnnouncementRepository>().create(
            title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text,
            body: _bodyCtrl.text,
            frequency: _frequency,
            expiresAt: _expiresAt,
          );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.announcementsNew,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: l.announcementsTitleField,
                  border: const OutlineInputBorder(),
                ),
                maxLength: 120,
              ),
              TextFormField(
                controller: _bodyCtrl,
                decoration: InputDecoration(
                  labelText: l.announcementsBodyField,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 6,
                maxLength: 2000,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l.announcementsBodyRequired
                    : null,
              ),
              const SizedBox(height: 12),
              // How often it re-appears for someone who's already seen it.
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'How often should it show?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in AnnouncementFrequency.all)
                    ChoiceChip(
                      label: Text(AnnouncementFrequency.label(f)),
                      selected: _frequency == f,
                      onSelected: (_) => setState(() => _frequency = f),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _frequencyHint(_frequency),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(_expiresAt == null
                    ? l.announcementsNoExpiry
                    : l.announcementsExpiresOn(
                        '${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}',
                      )),
                trailing: TextButton(
                  onPressed: _pickExpiry,
                  child: Text(_expiresAt == null
                      ? l.announcementsSetExpiry
                      : l.commonEdit),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.announcementsPublish),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
