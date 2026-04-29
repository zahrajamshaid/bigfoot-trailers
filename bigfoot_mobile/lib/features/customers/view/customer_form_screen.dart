import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/layout/responsive.dart';
import '../../../data/models/customer.dart';

class CustomerFormScreen extends StatefulWidget {
  final Customer? existing;
  final Future<void> Function(Customer customer) onSubmit;

  const CustomerFormScreen({
    super.key,
    this.existing,
    required this.onSubmit,
  });

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _company;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _billingAddress;
  late final TextEditingController _deliveryAddress;
  late final TextEditingController _notes;
  late String _type;
  bool _smsOptOut = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _company = TextEditingController(text: e?.company ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _billingAddress = TextEditingController(text: e?.billingAddress ?? '');
    _deliveryAddress = TextEditingController(text: e?.deliveryAddress ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _type = e?.customerType ?? CustomerType.endUser;
    _smsOptOut = e?.smsOptOut ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _phone.dispose();
    _email.dispose();
    _billingAddress.dispose();
    _deliveryAddress.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Create Customer' : 'Edit Customer'),
      ),
      body: Form(
        key: _form,
        child: ResponsiveContent(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _company,
              decoration: const InputDecoration(
                labelText: 'Company',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Customer Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: CustomerType.endUser, child: Text('End User')),
                DropdownMenuItem(value: CustomerType.dealer, child: Text('Dealer')),
                DropdownMenuItem(value: CustomerType.stockLocation, child: Text('Stock Location')),
              ],
              onChanged: (v) => setState(() => _type = v ?? CustomerType.endUser),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _billingAddress,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Billing Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _deliveryAddress,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Delivery Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _smsOptOut,
              onChanged: (v) => setState(() => _smsOptOut = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('SMS Opt-out'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(widget.existing == null ? 'Create Customer' : 'Save Changes'),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await widget.onSubmit(
        Customer(
          id: widget.existing?.id ?? 0,
          name: _name.text.trim(),
          company: _company.text.trim().isEmpty ? null : _company.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          customerType: _type,
          billingAddress: _billingAddress.text.trim().isEmpty
              ? null
              : _billingAddress.text.trim(),
          deliveryAddress: _deliveryAddress.text.trim().isEmpty
              ? null
              : _deliveryAddress.text.trim(),
          smsOptOut: _smsOptOut,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save customer: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
