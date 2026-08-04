import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/router/route_names.dart';
import '../data/support_api.dart';

/// Compose a new problem report. On submit it creates the ticket (which
/// notifies owner/office/PM) and drops the user into the thread so they can
/// follow up.
class ReportProblemScreen extends StatefulWidget {
  /// When opened from a trailer, its SO — prefills the subject for context.
  final String? prefillSo;
  const ReportProblemScreen({super.key, this.prefillSo});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final so = widget.prefillSo;
    if (so != null && so.isNotEmpty) {
      _subjectController.text = 'Trailer $so: ';
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = SupportApi(context.read<DioClient>());
      final ticket = await api.createTicket(
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report sent — an admin will get back to you.'),
        ),
      );
      // Replace this compose screen with the thread so back doesn't re-open it.
      context.pushReplacementNamed(
        RouteNames.supportThread,
        pathParameters: {'id': '${ticket.id}'},
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not send: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Having trouble with the app, or something not working right? '
                  'Send it here and it goes straight to the admins.',
                  style: TextStyle(fontSize: 13, color: AppColors.navy),
                ),
              ),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppColors.error)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _subjectController,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Short summary (e.g. "Can\'t mark delivery complete")',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 3) ? 'Add a short subject' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bodyController,
                maxLines: 6,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What\'s happening?',
                  hintText: 'Describe the problem and what you were doing.',
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Describe the problem' : null,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Sending…' : 'Send report'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
