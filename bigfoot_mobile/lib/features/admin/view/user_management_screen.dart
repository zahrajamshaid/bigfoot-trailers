import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/validation/validators.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
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
          content: Text(AppLocalizations.of(context).userMgmtLoadFail('$e')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final filtered = _users.where((u) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.userMgmtTitle),
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
                          decoration: InputDecoration(
                            labelText: l.userMgmtSearchHint,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _search = v.trim()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String?>(
                        value: _role,
                        hint: Text(l.userMgmtFilterRole),
                        items: [
                          DropdownMenuItem(value: null, child: Text(l.customersFilterAll)),
                          DropdownMenuItem(value: 'owner', child: Text(l.roleOwner)),
                          DropdownMenuItem(value: 'production_manager', child: Text(l.roleProductionManagerShort)),
                          DropdownMenuItem(value: 'transport_manager', child: Text(l.roleTransportManagerShort)),
                          DropdownMenuItem(value: 'qc_inspector', child: Text(l.roleQcShort)),
                          DropdownMenuItem(value: 'worker', child: Text(l.roleWorker)),
                          DropdownMenuItem(value: 'driver', child: Text(l.roleDriver)),
                          DropdownMenuItem(value: 'sales', child: Text(l.roleSales)),
                          DropdownMenuItem(value: 'office', child: Text(l.roleOffice)),
                          DropdownMenuItem(value: 'purchasing', child: Text(l.rolePurchasing)),
                        ],
                        onChanged: (v) {
                          setState(() => _role = v);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<bool?>(
                        value: _isActive,
                        hint: Text(l.userMgmtFilterStatus),
                        items: [
                          DropdownMenuItem(value: null, child: Text(l.customersFilterAll)),
                          DropdownMenuItem(value: true, child: Text(l.statusActive)),
                          DropdownMenuItem(value: false, child: Text(l.userMgmtInactive)),
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
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Text(
                                  l.userMgmtEmptyFiltered,
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
                                          child: Text(u.isActive == false
                                              ? l.userMgmtInactive
                                              : l.statusActive),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _detailChip(l.userMgmtIdChip(u.id)),
                                        _detailChip(l.userMgmtDeptChip(
                                          u.departmentId?.toString() ?? l.userMgmtNotAvailable,
                                        )),
                                        _detailChip(l.userMgmtLocationChip(
                                          u.locationId?.toString() ?? l.userMgmtNotAvailable,
                                        )),
                                        _detailChip(l.userMgmtCreatedChip(
                                          u.createdAt?.toLocal().toString().split('.').first ?? l.userMgmtNotAvailable,
                                        )),
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
                                          label: Text(l.commonEdit),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: u.isActive == false
                                              ? null
                                              : () => _confirmDeactivate(u),
                                          icon: const Icon(
                                              Icons.person_off_outlined,
                                              size: 16),
                                          label: Text(l.userMgmtDeactivate),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: u.isActive == false
                                              ? () => _reactivate(u)
                                              : null,
                                          icon: const Icon(
                                              Icons.person_add_alt_1,
                                              size: 16,
                                              color: AppColors.success),
                                          label: Text(
                                            l.userMgmtReactivate,
                                            style: const TextStyle(
                                                color: AppColors.success),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _confirmHardDelete(u),
                                          icon: const Icon(
                                              Icons.delete_forever_outlined,
                                              size: 16,
                                              color: AppColors.error),
                                          label: Text(
                                            l.commonDelete,
                                            style: const TextStyle(
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
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.userMgmtDeactivateTitle),
        content: Text(l.userMgmtDeactivateBody(user.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.userMgmtDeactivate),
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
        SnackBar(content: Text(l.userMgmtDeactivated(user.name))),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.commonFailed('$e'))));
    }
  }

  Future<void> _reactivate(User user) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AdminViewModel>().reactivateUser(user.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l.userMgmtReactivated(user.name))),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.commonFailed('$e'))));
    }
  }

  Future<void> _confirmHardDelete(User user) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.userMgmtDeleteTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.userMgmtDeleteBody(user.name)),
              const SizedBox(height: 8),
              Text(
                l.userMgmtDeleteHelper,
                style: const TextStyle(fontSize: 12, color: AppColors.disabled),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.userMgmtDeleteForever),
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
        SnackBar(content: Text(l.userMgmtDeleted(user.name))),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.userMgmtDeleteFail('$e'))));
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
    final l = AppLocalizations.of(context);
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
            Text(widget.existing == null ? l.userMgmtAdd : l.userMgmtEdit,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: l.userMgmtNameLabel,
                  border: const OutlineInputBorder()),
              validator: (v) =>
                  Validators.required(v, fieldName: 'a full name'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  labelText: l.loginEmail, border: const OutlineInputBorder()),
              validator: Validators.requiredEmail,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.existing == null
                    ? l.loginPassword
                    : l.userMgmtPasswordOptional,
                border: const OutlineInputBorder(),
              ),
              validator: widget.existing == null
                  ? Validators.password
                  : Validators.optionalPassword,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: InputDecoration(
                  labelText: l.userMgmtFilterRole,
                  border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: 'owner', child: Text(l.roleOwner)),
                DropdownMenuItem(value: 'production_manager', child: Text(l.roleProductionManager)),
                DropdownMenuItem(value: 'transport_manager', child: Text(l.roleTransportManager)),
                DropdownMenuItem(value: 'qc_inspector', child: Text(l.roleQcInspector)),
                DropdownMenuItem(value: 'worker', child: Text(l.roleWorker)),
                DropdownMenuItem(value: 'driver', child: Text(l.roleDriver)),
                DropdownMenuItem(value: 'sales', child: Text(l.roleSales)),
                DropdownMenuItem(value: 'office', child: Text(l.roleOffice)),
                DropdownMenuItem(value: 'purchasing', child: Text(l.rolePurchasing)),
              ],
              onChanged: (v) => setState(() => _role = v ?? UserRole.worker),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: l.userMgmtPhoneOptional,
                  border: const OutlineInputBorder()),
              validator: Validators.optionalPhone,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _dept,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: l.userMgmtDeptIdLabel,
                  border: const OutlineInputBorder()),
              validator: Validators.optionalPositiveInt,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _loc,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: l.userMgmtLocationIdLabel,
                  border: const OutlineInputBorder()),
              validator: Validators.optionalPositiveInt,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(widget.existing == null
                  ? l.userMgmtCreateAction
                  : l.commonSave),
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
        SnackBar(
            content:
                Text(AppLocalizations.of(context).commonFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
