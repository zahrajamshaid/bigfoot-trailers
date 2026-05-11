import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/validation/validators.dart';
import '../../../data/models/user.dart';
import '../viewmodel/admin_viewmodel.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _loading = true;
  String _search = '';
  String? _role;
  bool? _isActive;
  List<User> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await context.read<AdminViewModel>().getUsers(
            role: _role,
            isActive: _isActive,
            page: 1,
        limit: 100,
          );
      if (!mounted) return;
      // Newest first so a freshly-created user is at the top of the list.
      final sorted = [...result.users]..sort((a, b) => b.id.compareTo(a.id));
      setState(() => _users = sorted);
    } catch (e) {
      if (!mounted) return;
      setState(() => _users = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load users: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _users.where((u) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(onPressed: _openCreate, icon: const Icon(Icons.person_add_alt_1)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search name or email',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _search = v.trim()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String?>(
                        value: _role,
                        hint: const Text('Role'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: 'owner', child: Text('Owner')),
                          DropdownMenuItem(value: 'production_manager', child: Text('Prod Mgr')),
                          DropdownMenuItem(value: 'transport_manager', child: Text('Transport Mgr')),
                          DropdownMenuItem(value: 'qc_inspector', child: Text('QC')),
                          DropdownMenuItem(value: 'worker', child: Text('Worker')),
                          DropdownMenuItem(value: 'driver', child: Text('Driver')),
                          DropdownMenuItem(value: 'sales', child: Text('Sales')),
                          DropdownMenuItem(value: 'office', child: Text('Office')),
                        ],
                        onChanged: (v) {
                          setState(() => _role = v);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<bool?>(
                        value: _isActive,
                        hint: const Text('Status'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: true, child: Text('Active')),
                          DropdownMenuItem(value: false, child: Text('Inactive')),
                        ],
                        onChanged: (v) {
                          setState(() => _isActive = v);
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: const [
                              SizedBox(height: 80),
                              Center(
                                child: Text(
                                  'No registered users found for the current filters.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final u = filtered[i];
                              final isInactive = (u.isActive == false);
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isInactive
                                      ? AppColors.disabled.withValues(alpha: 0.08)
                                      : AppColors.white,
                                  border: Border.all(color: AppColors.divider),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: isInactive
                                                      ? AppColors.disabled
                                                      : AppColors.navy,
                                                ),
                                              ),
                                              Text(u.email,
                                                  style: const TextStyle(fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.navy.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(u.role),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: (u.isActive == false
                                                    ? AppColors.error
                                                    : AppColors.success)
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(u.isActive == false ? 'Inactive' : 'Active'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _detailChip('ID: ${u.id}'),
                                        _detailChip(
                                          'Dept: ${u.departmentId?.toString() ?? 'N/A'}',
                                        ),
                                        _detailChip(
                                          'Location: ${u.locationId?.toString() ?? 'N/A'}',
                                        ),
                                        _detailChip(
                                          'Created: ${u.createdAt?.toLocal().toString().split('.').first ?? 'N/A'}',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: () => _openEdit(u),
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 16),
                                          label: const Text('Edit'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: u.isActive == false
                                              ? null
                                              : () => _confirmDeactivate(u),
                                          icon: const Icon(
                                              Icons.person_off_outlined,
                                              size: 16),
                                          label: const Text('Deactivate'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: u.isActive == false
                                              ? () => _reactivate(u)
                                              : null,
                                          icon: const Icon(
                                              Icons.person_add_alt_1,
                                              size: 16,
                                              color: AppColors.success),
                                          label: const Text(
                                            'Reactivate',
                                            style: TextStyle(
                                                color: AppColors.success),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _confirmHardDelete(u),
                                          icon: const Icon(
                                              Icons.delete_forever_outlined,
                                              size: 16,
                                              color: AppColors.error),
                                          label: const Text(
                                            'Delete',
                                            style: TextStyle(
                                                color: AppColors.error),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                              color: AppColors.error
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _detailChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  Future<void> _openCreate() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _UserEditorSheet(),
    );
    if (result == true && mounted) {
      // Clear any active filters/search so the new user is guaranteed to be
      // visible after the refresh (otherwise the list looks "broken").
      setState(() {
        _search = '';
        _role = null;
        _isActive = null;
      });
      _load();
    }
  }

  Future<void> _openEdit(User user) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserEditorSheet(existing: user),
    );
    if (result == true && mounted) _load();
  }

  Future<void> _confirmDeactivate(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate user?'),
        content: Text(
          '${user.name} will lose access immediately but their history is '
          'preserved. You can reactivate later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AdminViewModel>().deactivateUser(user.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${user.name} deactivated')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _reactivate(User user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AdminViewModel>().reactivateUser(user.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${user.name} reactivated')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _confirmHardDelete(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently delete user?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently removes ${user.name} from the database. '
              'This cannot be undone.',
            ),
            const SizedBox(height: 8),
            const Text(
              'The user must be deactivated first. Users with historical '
              'activity (completed steps, inspections, deliveries, '
              'messages) cannot be deleted — keep them deactivated to '
              'preserve the audit trail.',
              style: TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AdminViewModel>().hardDeleteUser(user.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${user.name} deleted')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }
}

class _UserEditorSheet extends StatefulWidget {
  final User? existing;

  const _UserEditorSheet({this.existing});

  @override
  State<_UserEditorSheet> createState() => _UserEditorSheetState();
}

class _UserEditorSheetState extends State<_UserEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _phone;
  late final TextEditingController _dept;
  late final TextEditingController _loc;
  late String _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _email = TextEditingController(text: widget.existing?.email ?? '');
    _password = TextEditingController();
    _phone = TextEditingController();
    _dept = TextEditingController(
      text: widget.existing?.departmentId?.toString() ?? '',
    );
    _loc = TextEditingController(
      text: widget.existing?.locationId?.toString() ?? '',
    );
    _role = widget.existing?.role ?? UserRole.worker;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _dept.dispose();
    _loc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _form,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(widget.existing == null ? 'Create User' : 'Edit User',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              validator: (v) =>
                  Validators.required(v, fieldName: 'a full name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              validator: Validators.requiredEmail,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.existing == null ? 'Password' : 'Password (optional)',
                border: const OutlineInputBorder(),
              ),
              validator: widget.existing == null
                  ? Validators.password
                  : Validators.optionalPassword,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'owner', child: Text('Owner')),
                DropdownMenuItem(value: 'production_manager', child: Text('Production Manager')),
                DropdownMenuItem(value: 'transport_manager', child: Text('Transport Manager')),
                DropdownMenuItem(value: 'qc_inspector', child: Text('QC Inspector')),
                DropdownMenuItem(value: 'worker', child: Text('Worker')),
                DropdownMenuItem(value: 'driver', child: Text('Driver')),
                DropdownMenuItem(value: 'sales', child: Text('Sales')),
                DropdownMenuItem(value: 'office', child: Text('Office')),
              ],
              onChanged: (v) => setState(() => _role = v ?? UserRole.worker),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)', border: OutlineInputBorder()),
              validator: Validators.optionalPhone,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _dept,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Primary Department ID', border: OutlineInputBorder()),
              validator: Validators.optionalPositiveInt,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _loc,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Primary Location ID', border: OutlineInputBorder()),
              validator: Validators.optionalPositiveInt,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(widget.existing == null ? 'Create' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await context.read<AdminViewModel>().createUser(
              email: _email.text.trim(),
              fullName: _name.text.trim(),
              password: _password.text,
              role: _role,
              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              primaryDepartmentId: int.tryParse(_dept.text.trim()),
              primaryLocationId: int.tryParse(_loc.text.trim()),
            );
      } else {
        await context.read<AdminViewModel>().updateUser(
              id: widget.existing!.id,
              fullName: _name.text.trim(),
              email: _email.text.trim(),
              password: _password.text.trim().isEmpty ? null : _password.text,
              role: _role,
              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              primaryDepartmentId: int.tryParse(_dept.text.trim()),
              primaryLocationId: int.tryParse(_loc.text.trim()),
            );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
