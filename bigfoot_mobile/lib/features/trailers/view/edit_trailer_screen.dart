import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../data/models/customer.dart';
import '../../../data/models/trailer.dart';
import '../../../domain/repositories/storage_repository.dart';
import '../../../domain/repositories/trailer_repository.dart';
import '../../../shared/widgets/stock_location_chips.dart';
import '../viewmodel/trailers_viewmodel.dart';
import '../widgets/customer_picker_field.dart';

/// Edit form for an existing trailer. Mirrors [CreateTrailerScreen] field set
/// but submits via PATCH /trailers/:id and pre-fills from [trailer].
///
/// RBAC: visible only to roles that can also create — owner + production_manager.
/// Backend enforces the same on PATCH so UI gating is purely cosmetic.
class EditTrailerScreen extends StatefulWidget {
  final Trailer trailer;
  const EditTrailerScreen({super.key, required this.trailer});

  @override
  State<EditTrailerScreen> createState() => _EditTrailerScreenState();
}

class _EditTrailerScreenState extends State<EditTrailerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _soController;
  late final TextEditingController _colorController;
  late final TextEditingController _sizeController;
  late final TextEditingController _notesController;
  late final TextEditingController _specialNoteController;

  int? _selectedModelId;
  late bool _isStockBuild;
  int? _selectedStockLocationId;
  Customer? _selectedCustomer;

  bool _isSubmitting = false;
  String? _errorMessage;

  // Trailer models loaded from API
  List<_ModelOption> _modelOptions = const [];
  bool _loadingModels = true;
  String? _loadModelsError;

  // Replace QB PDF (optional)
  PlatformFile? _selectedPdf;
  String? _pdfWarning;

  // Inline error for the chip-style stock destination picker.
  String? _stockLocationError;

  @override
  void initState() {
    super.initState();
    final t = widget.trailer;
    _soController = TextEditingController(text: t.soNumber);
    _colorController = TextEditingController(text: t.color ?? '');
    _sizeController = TextEditingController(text: t.size ?? '');
    _notesController = TextEditingController(text: t.optionsNotes ?? '');
    _specialNoteController = TextEditingController(text: t.specialNote ?? '');
    _selectedModelId = t.trailerModelId;
    _isStockBuild = t.isStockBuild;
    _selectedStockLocationId =
        t.isStockBuild ? t.currentLocationId : null;
    if (t.customer != null) {
      _selectedCustomer = Customer(
        id: t.customer!.id,
        name: t.customer!.name,
        company: t.customer!.company,
        phone: t.customer!.smsPhone,
        email: t.customer!.email,
        customerType: t.customer!.customerType,
      );
    }
    _loadModels();
  }

  @override
  void dispose() {
    _soController.dispose();
    _colorController.dispose();
    _sizeController.dispose();
    _notesController.dispose();
    _specialNoteController.dispose();
    super.dispose();
  }

  /// Picker callback. If the returned (or freshly-created) customer is a
  /// stock_location, switch the form into Stock Build mode for that yard
  /// instead of assigning it as a regular customer.
  void _onCustomerPicked(Customer? c) {
    setState(() {
      if (c != null &&
          c.customerType == CustomerType.stockLocation &&
          c.stockLocationId != null) {
        _isStockBuild = true;
        _selectedStockLocationId = c.stockLocationId;
        _selectedCustomer = null;
        _stockLocationError = null;
      } else {
        _selectedCustomer = c;
      }
    });
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _loadModelsError = null;
    });
    try {
      final api = context.read<DioClient>();
      final response = await api.get<List<dynamic>>(
        ApiEndpoints.adminTrailerModels,
        fromJson: (d) => d as List<dynamic>,
      );
      final options = (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map((m) => _ModelOption(
                id: (m['id'] as num).toInt(),
                displayName: (m['displayName'] as String?) ??
                    (m['code'] as String?) ??
                    'Model ${m['id']}',
                series: (m['series'] as String?) ?? '',
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        _modelOptions = options;
        _loadingModels = false;
        _loadModelsError = options.isEmpty
            ? 'No trailer models are configured on the server.'
            : null;
        // If the trailer's current model isn't in the loaded list (rare),
        // clear the selection so the validator forces a pick.
        if (_selectedModelId != null &&
            !options.any((m) => m.id == _selectedModelId)) {
          _selectedModelId = null;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _modelOptions = const [];
        _loadingModels = false;
        _loadModelsError = e.displayMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _modelOptions = const [];
        _loadingModels = false;
        _loadModelsError = 'Could not load trailer models. Check your connection.';
      });
    }
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) {
        setState(() => _pdfWarning = 'Could not read the selected PDF file.');
        return;
      }
      setState(() {
        _selectedPdf = file;
        _pdfWarning = null;
      });
    } catch (_) {
      setState(() => _pdfWarning = 'Unable to open the file picker.');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isStockBuild && _selectedStockLocationId == null) {
      setState(() {
        _stockLocationError = 'Pick a stock destination';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _pdfWarning = null;
      _stockLocationError = null;
    });

    try {
      final repo = context.read<TrailerRepository>();
      final storageRepo = context.read<StorageRepository>();
      final t = widget.trailer;

      // Send only fields whose value actually differs from the loaded trailer.
      // PATCH on backend treats `undefined` as "leave alone" and `null` as
      // "clear" — see UpdateTrailerDto + trailers.service.update().
      final payload = <String, dynamic>{};

      final soNumber = _soController.text.trim();
      if (soNumber != t.soNumber) payload['soNumber'] = soNumber;

      if (_selectedModelId != null && _selectedModelId != t.trailerModelId) {
        payload['trailerModelId'] = _selectedModelId;
      }

      final color = _colorController.text.trim();
      if (color != (t.color ?? '')) payload['color'] = color;

      final size = _sizeController.text.trim();
      if (size != (t.size ?? '')) payload['sizeFt'] = size;

      final notes = _notesController.text.trim();
      if (notes != (t.optionsNotes ?? '')) payload['optionsNotes'] = notes;

      final specialNote = _specialNoteController.text.trim();
      if (specialNote != (t.specialNote ?? '')) {
        payload['specialNote'] = specialNote;
      }

      if (_isStockBuild != t.isStockBuild) {
        payload['isStockBuild'] = _isStockBuild;
      }
      if (_isStockBuild && _selectedStockLocationId != null) {
        payload['stockLocationId'] = _selectedStockLocationId;
      }

      if (!_isStockBuild) {
        final newCustomerId = _selectedCustomer?.id;
        if (newCustomerId != t.customerId) {
          payload['customerId'] = newCustomerId; // null clears
        }
      } else if (t.customerId != null) {
        payload['customerId'] = null; // stock build cleared customer
      }

      if (payload.isNotEmpty) {
        await repo.updateTrailer(t.id, payload);
      }

      String? pdfWarning;
      if (_selectedPdf != null) {
        pdfWarning = await _uploadPdf(
          trailerId: t.id,
          trailerRepo: repo,
          storageRepo: storageRepo,
          file: _selectedPdf!,
        );
      }

      if (!mounted) return;
      context.read<TrailersViewModel>().load();

      final message = pdfWarning == null
          ? 'Trailer $soNumber updated'
          : 'Trailer updated. PDF upload failed: $pdfWarning';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              pdfWarning == null ? AppColors.success : AppColors.warning,
        ),
      );
      context.pop(true);
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.displayMessage;
        _isSubmitting = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Failed to update trailer';
        _isSubmitting = false;
      });
    }
  }

  Future<String?> _uploadPdf({
    required int trailerId,
    required TrailerRepository trailerRepo,
    required StorageRepository storageRepo,
    required PlatformFile file,
  }) async {
    try {
      final result = await storageRepo.uploadFile(
        fileType: 'so_pdf',
        trailerId: trailerId,
        fileName: file.name,
        bytes: file.bytes!,
        contentType: 'application/pdf',
      );
      if (result.queued || result.storageKey == null) {
        return 'no network — PDF will retry later';
      }
      final storageKey = result.storageKey!;
      await trailerRepo.uploadQbPdf(
        trailerId: trailerId,
        storageKey: storageKey,
        storageUrl: storageKey,
      );
      return null;
    } on ApiException catch (e) {
      return e.displayMessage;
    } catch (e) {
      return e.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.trailer.soNumber}')),
      body: _loadingModels
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _modelOptions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(
                          _loadModelsError ?? 'No trailer models available.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadModels,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppColors.error, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _soController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'SO Number *',
                            prefixIcon: Icon(Icons.tag),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'SO number is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: _selectedModelId,
                          decoration: const InputDecoration(
                            labelText: 'Trailer Model *',
                            prefixIcon: Icon(Icons.local_shipping_outlined),
                          ),
                          items: _modelOptions
                              .map((m) => DropdownMenuItem(
                                    value: m.id,
                                    child: Text(m.displayName),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedModelId = v),
                          validator: (v) =>
                              v == null ? 'Select a trailer model' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _colorController,
                          decoration: const InputDecoration(
                            labelText: 'Color',
                            prefixIcon: Icon(Icons.palette_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _sizeController,
                          decoration: const InputDecoration(
                            labelText: 'Size (ft)',
                            prefixIcon: Icon(Icons.straighten),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Options / Notes',
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(bottom: 48),
                              child: Icon(Icons.notes),
                            ),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _specialNoteController,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            labelText: 'Special Note',
                            hintText: 'e.g. ship empty, hold for VIN check',
                            prefixIcon: Icon(Icons.sticky_note_2_outlined),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Stock Build'),
                          subtitle: const Text('No customer assigned'),
                          value: _isStockBuild,
                          activeColor: AppColors.amber,
                          onChanged: (v) => setState(() {
                            _isStockBuild = v;
                            if (v) {
                              _selectedCustomer = null;
                            } else {
                              _selectedStockLocationId = null;
                            }
                          }),
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_isStockBuild) ...[
                          const SizedBox(height: 12),
                          StockLocationChips(
                            labelText: 'Stock Destination *',
                            selectedLocationId: _selectedStockLocationId,
                            enabled: !_isSubmitting,
                            onChanged: (l) => setState(() {
                              _selectedStockLocationId = l.id;
                              _stockLocationError = null;
                            }),
                            errorText: _stockLocationError,
                          ),
                        ],
                        if (!_isStockBuild) ...[
                          const SizedBox(height: 12),
                          CustomerPickerField(
                            selectedCustomerId: _selectedCustomer?.id,
                            selectedCustomerLabel: _selectedCustomer == null
                                ? null
                                : (_selectedCustomer!.company?.isNotEmpty == true
                                    ? '${_selectedCustomer!.name} (${_selectedCustomer!.company})'
                                    : _selectedCustomer!.name),
                            onChanged: _onCustomerPicked,
                            helperText:
                                'Optional — leave blank for unassigned builds',
                          ),
                        ],
                        const SizedBox(height: 16),
                        _PdfPickerTile(
                          existingKey: widget.trailer.qbSoPdfStorageKey,
                          selectedFile: _selectedPdf,
                          onPick: _isSubmitting ? null : _pickPdf,
                          onClear: _isSubmitting
                              ? null
                              : () => setState(() => _selectedPdf = null),
                          warning: _pdfWarning,
                        ),
                        const SizedBox(height: 24),
                        Builder(
                          builder: (context) {
                            final safeBottom =
                                MediaQuery.of(context).viewPadding.bottom;
                            return Padding(
                              padding: EdgeInsets.only(bottom: safeBottom + 12),
                              child: SizedBox(
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isSubmitting ? null : _submit,
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: AppColors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Save Changes',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _ModelOption {
  final int id;
  final String displayName;
  final String series;
  const _ModelOption({
    required this.id,
    required this.displayName,
    required this.series,
  });
}

class _PdfPickerTile extends StatelessWidget {
  final String? existingKey;
  final PlatformFile? selectedFile;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final String? warning;

  const _PdfPickerTile({
    required this.existingKey,
    required this.selectedFile,
    required this.onPick,
    required this.onClear,
    required this.warning,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final hasNew = selectedFile != null;
    final hasExisting = existingKey != null && existingKey!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.disabled.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined, color: AppColors.navy),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'QB Sales Order PDF',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (hasNew)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Discard new PDF',
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (hasNew) ...[
            Text(
              selectedFile!.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _formatSize(selectedFile!.size),
              style: const TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          ] else if (hasExisting)
            const Text(
              'A PDF is already attached. Pick a new file to replace it.',
              style: TextStyle(fontSize: 12, color: AppColors.disabled),
            )
          else
            const Text(
              'Optional — attach the QuickBooks SO PDF for this trailer.',
              style: TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(hasNew || hasExisting ? 'Replace PDF' : 'Attach PDF'),
          ),
          if (warning != null) ...[
            const SizedBox(height: 6),
            Text(
              warning!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}
