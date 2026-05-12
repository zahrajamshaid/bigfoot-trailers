import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/customer.dart';
import '../../../data/models/user.dart';
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
        SnackBar(content: Text('Unable to load customer detail: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final customer = detail?.customer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Detail'),
        actions: [
          IconButton(
            onPressed: customer == null || _deleting ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          if (_canDelete)
            IconButton(
              tooltip: 'Delete customer',
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
          tabs: const [
            Tab(text: 'Trailer History'),
            Tab(text: 'Delivery History'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : detail == null
              ? const Center(child: Text('Customer not found'))
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
          title: const Text('Delete customer?'),
          content: Text('This permanently deletes "${existing.name}".'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
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
          title: const Text('Customer has trailers'),
          content: Text(
            '"${existing.name}" is referenced by $trailerCount '
            'trailer${trailerCount == 1 ? '' : 's'}.\n\n'
            'Deleting the customer will also delete every associated '
            'trailer along with its production history, QC inspections, '
            'photos, deliveries, and messages.\n\n'
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete customer + $trailerCount trailers'),
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
                ? 'Deleted "${existing.name}" and $trailerCount trailer'
                    '${trailerCount == 1 ? '' : 's'}'
                : 'Deleted customer "${existing.name}"',
          ),
        ),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _toggleSms(bool value) async {
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
        SnackBar(content: Text('Failed to update SMS preference: $e')),
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
          Text('Phone: ${customer.phone ?? '-'}'),
          Text('Email: ${customer.email ?? '-'}'),
          Text('QuickBooks ID: ${customer.quickbooksCustomerId ?? '-'}'),
          SwitchListTile(
            value: customer.smsOptOut,
            onChanged: savingSms ? null : onToggleSms,
            contentPadding: EdgeInsets.zero,
            title: const Text('SMS Opt-out'),
            subtitle: savingSms ? const Text('Updating...') : null,
          ),
          const SizedBox(height: 8),
          Text('Billing Address: ${customer.billingAddress ?? '-'}'),
          Text('Delivery Address: ${customer.deliveryAddress ?? '-'}'),
          const SizedBox(height: 8),
          Text('Notes: ${customer.notes ?? '-'}'),
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
    if (items.isEmpty) {
      return const Center(child: Text('No trailer history'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final t = items[i];
        return Card(
          child: ListTile(
            title: Text(t.soNumber),
            subtitle: Text('VIN: ${t.vinNumber ?? '-'}\nStatus: ${t.status}'),
            trailing: OutlinedButton(
              onPressed: () {
                if (t.trailerId > 0) {
                  context.pushNamed(
                    RouteNames.trailerDetail,
                    pathParameters: {'id': '${t.trailerId}'},
                  );
                }
              },
              child: const Text('Open'),
            ),
          ),
        );
      },
    );
  }
}

class _DeliveryHistoryList extends StatelessWidget {
  final List<CustomerDeliveryHistoryItem> items;

  const _DeliveryHistoryList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('No delivery history'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = items[i];
        return Card(
          child: ListTile(
            title: Text('Delivery #${d.deliveryId}'),
            subtitle: Text(
              'Trailer: ${d.trailerId ?? '-'}\n'
              'Type: ${d.deliveryType ?? '-'} • Status: ${d.status}',
            ),
            trailing: OutlinedButton(
              onPressed: () {
                context.pushNamed(
                  RouteNames.deliveryDetail,
                  pathParameters: {'id': '${d.deliveryId}'},
                );
              },
              child: const Text('Open'),
            ),
          ),
        );
      },
    );
  }
}
