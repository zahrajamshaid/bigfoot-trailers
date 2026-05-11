import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/validation/validators.dart';
import '../../../data/models/customer.dart';
import '../../../shared/widgets/stock_location_chips.dart';
import '../../customers/viewmodel/customers_viewmodel.dart';

/// Form field that lets the user pick a customer for a trailer.
///
/// Tapping the field opens a search-driven bottom sheet that hits
/// `/customers?search=...` via [CustomersViewModel]. A "Clear" affordance
/// is shown when a customer is already selected.
class CustomerPickerField extends StatelessWidget {
  final int? selectedCustomerId;
  final String? selectedCustomerLabel;
  final ValueChanged<Customer?> onChanged;
  final bool enabled;
  final String? helperText;

  const CustomerPickerField({
    super.key,
    required this.selectedCustomerId,
    required this.selectedCustomerLabel,
    required this.onChanged,
    this.enabled = true,
    this.helperText,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<Customer?>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerSearchSheet(
        viewModel: context.read<CustomersViewModel>(),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCustomerId != null;
    final label = selectedCustomerLabel?.trim().isNotEmpty == true
        ? selectedCustomerLabel!
        : (hasSelection ? 'Customer #$selectedCustomerId' : 'Tap to pick a customer');

    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Customer',
          helperText: helperText,
          prefixIcon: const Icon(Icons.person_outline),
          suffixIcon: hasSelection
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear customer',
                  onPressed: enabled ? () => onChanged(null) : null,
                )
              : const Icon(Icons.search, size: 20),
        ),
        isEmpty: !hasSelection,
        child: Text(
          hasSelection ? label : '',
          style: TextStyle(
            color: hasSelection ? null : AppColors.disabled,
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _CustomerSearchSheet extends StatefulWidget {
  final CustomersViewModel viewModel;
  const _CustomerSearchSheet({required this.viewModel});

  @override
  State<_CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends State<_CustomerSearchSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<Customer> _items = const [];

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.viewModel.getCustomers(
        query: query.trim().isEmpty ? null : query.trim(),
        // Stock yards belong to the chip picker, not here.
        excludeStockLocations: true,
        page: 1,
        limit: 25,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
        _error = 'Could not load customers: $e';
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(value));
  }

  Future<void> _openCreateCustomerDialog() async {
    final created = await showDialog<Customer?>(
      context: context,
      builder: (_) => _CreateCustomerDialog(viewModel: widget.viewModel),
    );
    if (created != null && mounted) {
      // Pop the picker sheet with the freshly-created customer so the
      // calling form (Create / Edit Trailer) gets it as the selection.
      Navigator.of(context).pop(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.disabled.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pick a customer',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search by name, company, phone, email',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(height: 8),
              // Inline "create new customer" entry — sits above the search
              // results so it's always one tap away without scrolling.
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_add_alt_1,
                      color: AppColors.amber, size: 20),
                ),
                title: const Text(
                  'Create new customer',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  "Don't see them? Add a customer here — they'll show up under Customers too.",
                  style: TextStyle(fontSize: 12),
                ),
                onTap: _openCreateCustomerDialog,
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.amber),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                          )
                        : _items.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No matching customers — try the "Create new customer" option above.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.disabled),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final c = _items[i];
                                  final subtitle = [
                                    if (c.company != null && c.company!.isNotEmpty)
                                      c.company!,
                                    if (c.phone != null && c.phone!.isNotEmpty)
                                      c.phone!,
                                  ].join(' · ');
                                  return ListTile(
                                    leading: const Icon(Icons.person),
                                    title: Text(c.name),
                                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                                    onTap: () => Navigator.of(context).pop(c),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim inline form for creating a customer from the picker. Posts to the
/// same `/customers` endpoint the Customers screen uses, so the new row
/// shows up there immediately too. Returns the created [Customer] on save.
class _CreateCustomerDialog extends StatefulWidget {
  final CustomersViewModel viewModel;
  const _CreateCustomerDialog({required this.viewModel});

  @override
  State<_CreateCustomerDialog> createState() => _CreateCustomerDialogState();
}

class _CreateCustomerDialogState extends State<_CreateCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _customerType = CustomerType.endUser;
  int? _stockLocationId;
  String? _stockLocationError;
  bool _saving = false;
  String? _error;

  bool get _isStock => _customerType == CustomerType.stockLocation;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isStock && _stockLocationId == null) {
      setState(() => _stockLocationError = 'Pick which yard this customer represents');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _stockLocationError = null;
    });
    try {
      final draft = Customer(
        id: 0, // assigned by backend
        name: _nameCtrl.text.trim(),
        company: _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        customerType: _customerType,
        stockLocationId: _isStock ? _stockLocationId : null,
      );
      final created = await widget.viewModel.createCustomer(draft);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to create customer: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Customer'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    Validators.required(v, fieldName: 'a customer name'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _companyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Company',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: Validators.optionalPhone,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: Validators.optionalEmail,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _customerType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  prefixIcon: Icon(Icons.category_outlined),
                  helperText:
                      'Picking "Stock Location" auto-converts the trailer into a stock build for that yard.',
                ),
                items: const [
                  DropdownMenuItem(
                      value: CustomerType.endUser, child: Text('End User')),
                  DropdownMenuItem(
                      value: CustomerType.dealer, child: Text('Dealer')),
                  DropdownMenuItem(
                      value: CustomerType.stockLocation,
                      child: Text('Stock Location')),
                ],
                onChanged: (v) => setState(() {
                  _customerType = v ?? CustomerType.endUser;
                  if (!_isStock) _stockLocationId = null;
                }),
              ),
              if (_isStock) ...[
                const SizedBox(height: 12),
                StockLocationChips(
                  labelText: 'Yard *',
                  selectedLocationId: _stockLocationId,
                  enabled: !_saving,
                  onChanged: (l) => setState(() {
                    _stockLocationId = l.id;
                    _stockLocationError = null;
                  }),
                  errorText: _stockLocationError,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
