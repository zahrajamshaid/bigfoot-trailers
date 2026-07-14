import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../data/trailer_options_api.dart';

typedef _Dept = ({int id, String code, String name});

/// Add an option to a trailer.
///
/// The department is REQUIRED, and that's the whole point: the department that
/// fits an option is the one that must acknowledge it before it can complete
/// its step. An option with no department is visible to everyone and blocks
/// nobody — which is exactly the hole that lets D-rings get missed. So the form
/// won't submit without one.
///
/// If the build has already started, the API flags the option for the
/// production manager's dashboard; this dialog warns the user that will happen.
class AddOptionDialog extends StatefulWidget {
  final int trailerId;

  /// True when the trailer is already being built — adding now raises an alert.
  final bool inProduction;

  const AddOptionDialog({
    super.key,
    required this.trailerId,
    this.inProduction = false,
  });

  @override
  State<AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<AddOptionDialog> {
  late final TrailerOptionsApi _api;
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  List<_Dept> _departments = const [];
  final Set<int> _deptIds = {};
  bool _loading = true;
  bool _saving = false;
  String? _deptError;

  @override
  void initState() {
    super.initState();
    _api = TrailerOptionsApi(context.read<DioClient>());
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final d = await _api.installDepartments();
      if (!mounted) return;
      setState(() {
        _departments = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to load departments: $e')));
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_deptIds.isEmpty) {
      setState(() => _deptError = 'Pick at least one department that fits this');
      return;
    }

    setState(() {
      _deptError = null;
      _saving = true;
    });
    try {
      await _api.addOption(
        trailerId: widget.trailerId,
        addonName: name,
        installDepartmentIds: _deptIds.toList(),
        notes: _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      final codes = _departments
          .where((d) => _deptIds.contains(d.id))
          .map((d) => d.code)
          .join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.inProduction
                ? 'Added — $codes must each acknowledge it, and the production manager has been alerted'
                : 'Added — $codes must each acknowledge it during the build',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add option'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.amber)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Adding to a trailer that's already being built is the
                  // dangerous case — say so plainly.
                  if (widget.inProduction) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18, color: AppColors.warning),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This trailer is already in production. The '
                              'production manager will be alerted.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Option',
                      hintText: 'e.g. Extra D-rings (x2)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // WHO FITS IT — one or more departments. An option can need
                  // several (D-rings welded at JIG, touched up at PAINT), and
                  // EACH must acknowledge its own part before it can complete
                  // its step. At least one is required, otherwise the option
                  // would block nobody.
                  Text(
                    'Who fits this?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _deptError != null
                          ? AppColors.error
                          : AppColors.navy,
                    ),
                  ),
                  const Text(
                    'Pick every department involved — each must acknowledge its '
                    'part before it can complete its step.',
                    style: TextStyle(fontSize: 11, color: AppColors.disabled),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _departments.map((d) {
                          final on = _deptIds.contains(d.id);
                          return FilterChip(
                            selected: on,
                            label: Text(d.code,
                                style: const TextStyle(fontSize: 12)),
                            tooltip: d.name,
                            onSelected: (v) => setState(() {
                              if (v) {
                                _deptIds.add(d.id);
                              } else {
                                _deptIds.remove(d.id);
                              }
                              _deptError = null;
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (_deptError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_deptError!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.error)),
                    ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Anything the fitter needs to know',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _nameController.text.trim().isEmpty
              ? null
              : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Add option'),
        ),
      ],
    );
  }
}
