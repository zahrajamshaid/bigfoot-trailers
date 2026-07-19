import 'dart:async';

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

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _filterType;
  int _page = 1;
  int _totalPages = 1;
  List<Customer> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _syncing = false;

  /// Only owner/office run the QuickBooks sync (matches the backend @Roles on
  /// POST /customers/sync). Sales can see and edit customers but not bulk-sync.
  bool get _canSync {
    final auth = context.read<AuthViewModel>().state;
    if (auth is! Authenticated) return false;
    return auth.user.role == UserRole.owner || auth.user.role == UserRole.office;
  }

  Future<void> _syncWithQuickBooks() async {
    setState(() => _syncing = true);
    try {
      final summary = await context.read<CustomersViewModel>().syncWithQuickBooks();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(summary)));
      await _load(); // refresh the list with anything pulled in
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await context.read<CustomersViewModel>().getCustomers(
            query: _searchController.text.trim(),
            customerType: _filterType,
            page: _page,
            limit: 20,
          );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _totalPages = (result.total / result.limit).ceil().clamp(1, 99999);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _totalPages = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).customersLoadFail('$e'))),
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
    return Scaffold(
      body: Column(
        children: [
          // Title + sync live in the body (not a second app bar) so the sync
          // button is always visible. Sync is owner/office only.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Text(l.customersTitle,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_canSync)
                  _syncing
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: _syncWithQuickBooks,
                          icon: const Icon(Icons.sync, size: 18),
                          label: const Text('Sync with QuickBooks'),
                        ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: l.customersSearchHint,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        _page = 1;
                        _load();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String?>(
                  value: _filterType,
                  hint: Text(l.customersFilterType),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.customersFilterAll)),
                    DropdownMenuItem(value: CustomerType.endUser, child: Text(l.customerTypeEndUser)),
                    DropdownMenuItem(value: CustomerType.dealer, child: Text(l.customerTypeDealer)),
                    DropdownMenuItem(value: CustomerType.stockLocation, child: Text(l.customerTypeStockLoc)),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _filterType = v;
                      _page = 1;
                    });
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final c = _items[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final result = await context.pushNamed<bool>(
                              RouteNames.customerDetail,
                              pathParameters: {'id': '${c.id}'},
                            );
                            if (result == true && mounted) _load();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    _TypeBadge(type: c.customerType),
                                  ],
                                ),
                                if (c.company?.isNotEmpty == true)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(c.company!),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  children: [
                                    _Meta(icon: Icons.phone_outlined, text: c.phone ?? '-'),
                                    _Meta(icon: Icons.email_outlined, text: c.email ?? '-'),
                                    _Meta(
                                      icon: Icons.local_shipping_outlined,
                                      text: l.customersActiveTrailers(c.activeTrailerCount),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCustomer,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(l.customersNew),
      ),
    );
  }

  Future<void> _createCustomer() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          onSubmit: (customer) => context.read<CustomersViewModel>().createCustomer(customer),
        ),
      ),
    );
    if (created == true && mounted) {
      _load();
    }
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.disabled),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.disabled)),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (label, color) = switch (type) {
      CustomerType.dealer => (l.customerTypeDealer, Colors.blue),
      CustomerType.stockLocation => (l.customerTypeStockShort, Colors.orange),
      _ => (l.customerTypeEndUser, Colors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
