import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/customer.dart';
import '../../../data/models/user.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../viewmodel/customers_viewmodel.dart';
import 'customer_form_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final int customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  bool _savingSms = false;
  bool _deleting = false;
  CustomerDetail? _detail;

  bool get _canDelete {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return false;
    return auth.user.role == UserRole.owner;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail =
          await context.read<CustomersViewModel>().getCustomerDetail(widget.customerId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _detail = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).customerDetailLoadFail('$e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final detail = _detail;
    final customer = detail?.customer;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.customerDetailTitle),
        actions: [
          IconButton(
            onPressed: customer == null || _deleting ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          if (_canDelete)
            IconButton(
              tooltip: l.customerDetailDeleteTooltip,
              onPressed: customer == null || _deleting ? null : _confirmDelete,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, color: AppColors.error),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l.customerDetailTabTrailers),
            Tab(text: l.customerDetailTabDeliveries),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : detail == null
              ? Center(child: Text(l.customerDetailNotFound))
              : Column(
                  children: [
                    _ContactCard(
                      customer: detail.customer,
                      savingSms: _savingSms,
                      onToggleSms: _toggleSms,
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _TrailerHistoryList(items: detail.trailerHistory),
                          _DeliveryHistoryList(items: detail.deliveryHistory),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Future<void> _edit() async {
    final existing = _detail?.customer;
    if (existing == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          existing: existing,
          onSubmit: (updated) => context.read<CustomersViewModel>().updateCustomer(updated),
        ),
      ),
    );

    if (saved == true && mounted) {
      _load();
    }
  }

  Future<void> _confirmDelete() async {
    final l = AppLocalizations.of(context);
    final detail = _detail;
    final existing = detail?.customer;
    if (existing == null || detail == null) return;

    final trailerCount = detail.trailerHistory.length;
    final bool? choice;

    if (trailerCount == 0) {
      // Simple path: no trailers — single confirm.
      choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.customerDetailDeleteTitle),
          content: Text(l.customerDetailDeleteBody(existing.name)),
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
    } else {
      // Customer has trailers — explicit cascade confirmation.
      // Returns true ONLY if the user picks the cascade option.
      choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.customerDetailHasTrailersTitle),
          content: Text(l.customerDetailHasTrailersBody(
              existing.name, trailerCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.customerDetailDeleteCascade(trailerCount)),
            ),
          ],
        ),
      );
    }

    if (choice != true || !mounted) return;

    final cascade = trailerCount > 0;
    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context
          .read<CustomersViewModel>()
          .deleteCustomer(widget.customerId, cascadeTrailers: cascade);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            cascade
                ? l.customerDetailDeletedCascade(existing.name, trailerCount)
                : l.customerDetailDeleted(existing.name),
          ),
        ),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l.customerDetailDeleteFailed('$e'))),
      );
    }
  }

  Future<void> _toggleSms(bool value) async {
    final l = AppLocalizations.of(context);
    final existing = _detail?.customer;
    if (existing == null) return;

    setState(() => _savingSms = true);
    try {
      final updated = await context.read<CustomersViewModel>().updateCustomer(
            Customer(
              id: existing.id,
              name: existing.name,
              company: existing.company,
              phone: existing.phone,
              email: existing.email,
              customerType: existing.customerType,
              billingAddress: existing.billingAddress,
              deliveryAddress: existing.deliveryAddress,
              smsOptOut: value,
              notes: existing.notes,
            ),
          );
      if (!mounted) return;
      setState(() {
        _detail = CustomerDetail(
          customer: updated,
          trailerHistory: _detail!.trailerHistory,
          deliveryHistory: _detail!.deliveryHistory,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.customerDetailSmsUpdateFailed('$e'))),
      );
    } finally {
      if (mounted) {
        setState(() => _savingSms = false);
      }
    }
  }
}

class _ContactCard extends StatelessWidget {
  final Customer customer;
  final bool savingSms;
  final ValueChanged<bool> onToggleSms;

  const _ContactCard({
    required this.customer,
    required this.savingSms,
    required this.onToggleSms,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.white,
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customer.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          if (customer.company?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(customer.company!),
            ),
          const SizedBox(height: 10),
          Text(l.customerDetailPhone(customer.phone ?? '-')),
          Text(l.customerDetailEmail(customer.email ?? '-')),
          Text(l.customerDetailQbId(customer.quickbooksCustomerId ?? '-')),
          SwitchListTile(
            value: customer.smsOptOut,
            onChanged: savingSms ? null : onToggleSms,
            contentPadding: EdgeInsets.zero,
            title: Text(l.customerFormSmsOptOut),
            subtitle: savingSms ? Text(l.customerDetailUpdating) : null,
          ),
          const SizedBox(height: 8),
          Text(l.customerDetailBilling(customer.billingAddress ?? '-')),
          Text(l.customerDetailDelivery(customer.deliveryAddress ?? '-')),
          const SizedBox(height: 8),
          Text(l.customerDetailNotes(customer.notes ?? '-')),
        ],
      ),
    );
  }
}

class _TrailerHistoryList extends StatelessWidget {
  final List<CustomerTrailerHistoryItem> items;

  const _TrailerHistoryList({required this.items});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Center(child: Text(l.customerDetailNoTrailerHistory, style: _emptyStyle));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final t = items[i];
        return Card(
          color: AppColors.white,
          child: ListTile(
            title: Text('SO #${t.soNumber}', style: _titleStyle),
            subtitle: Text(
              '${t.model ?? '-'}\n'
              '${l.customerDetailStatusValue(t.status)}',
              style: _subtitleStyle,
            ),
            trailing: OutlinedButton(
              onPressed: () {
                if (t.trailerId > 0) {
                  context.pushNamed(
                    RouteNames.trailerDetail,
                    pathParameters: {'id': '${t.trailerId}'},
                  );
                }
              },
              child: Text(l.customerDetailOpen),
            ),
          ),
        );
      },
    );
  }
}

// Shared, high-contrast text styles for the customer history lists so the
// content reads clearly against the white cards (the M3 defaults were faint).
const TextStyle _titleStyle =
    TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 15);
const TextStyle _subtitleStyle =
    TextStyle(color: AppColors.navy, height: 1.4);
const TextStyle _emptyStyle =
    TextStyle(color: AppColors.navy, fontSize: 14, fontWeight: FontWeight.w500);

class _DeliveryHistoryList extends StatelessWidget {
  final List<CustomerDeliveryHistoryItem> items;

  const _DeliveryHistoryList({required this.items});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Center(child: Text(l.customerDetailNoDeliveryHistory, style: _emptyStyle));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = items[i];
        return Card(
          color: AppColors.white,
          child: ListTile(
            title: Text(l.customerDetailDeliveryHash(d.deliveryId), style: _titleStyle),
            subtitle: Text(
              '${l.customerDetailTrailerValue('${d.trailerId ?? '-'}')}\n'
              '${l.customerDetailTypeStatus(d.deliveryType ?? '-', d.status)}',
              style: _subtitleStyle,
            ),
            trailing: OutlinedButton(
              onPressed: () {
                context.pushNamed(
                  RouteNames.deliveryDetail,
                  pathParameters: {'id': '${d.deliveryId}'},
                );
              },
              child: Text(l.customerDetailOpen),
            ),
          ),
        );
      },
    );
  }
}
