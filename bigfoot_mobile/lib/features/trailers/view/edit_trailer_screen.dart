import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../data/models/trailer.dart';
import '../../../domain/repositories/storage_repository.dart';
import '../../../domain/repositories/trailer_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/stock_location_chips.dart';
import '../viewmodel/trailers_viewmodel.dart';

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
  late final TextEditingController _customerController;

  int? _selectedModelId;
  late bool _isStockBuild;
  int? _selectedStockLocationId;

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
    // Customer is now plain text — prefill from a legacy customer record if
    // one exists, otherwise from the free-text name.
    _customerController =
        TextEditingController(text: t.customer?.name ?? t.soldToName ?? '');
    _selectedModelId = t.trailerModelId;
    _isStockBuild = t.isStockBuild;
    _selectedStockLocationId =
        t.isStockBuild ? t.currentLocationId : null;
    _loadModels();
  }

  @override
  void dispose() {
    _soController.dispose();
    _colorController.dispose();
    _sizeController.dispose();
    _notesController.dispose();
    _specialNoteController.dispose();
    _customerController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _loadModelsError = null;
    });
    try {
      final api = context.read<DioClient>();
      final l = AppLocalizations.of(context);
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
                    l.createTrailerModelFallback('${m['id']}'),
                series: (m['series'] as String?) ?? '',
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        _modelOptions = options;
        _loadingModels = false;
        _loadModelsError =
            options.isEmpty ? l.createTrailerModelsEmpty : null;
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
        _loadModelsError =
            AppLocalizations.of(context).createTrailerModelsLoadFail;
      });
    }
  }

  Future<void> _pickPdf() async {
    final l = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) {
        setState(() => _pdfWarning = l.createTrailerPickPdfFail);
        return;
      }
      setState(() {
        _selectedPdf = file;
        _pdfWarning = null;
      });
    } catch (_) {
      setState(() => _pdfWarning = l.createTrailerPickerOpenFail);
    }
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_isStockBuild && _selectedStockLocationId == null) {
      setState(() {
        _stockLocationError = l.createTrailerStockDestRequired;
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

      // Customer / sold-to name is independent of the stock-build flag.
      // Submitting a non-empty name marks the trailer sold (server sets
      // saleStatus); an empty string clears the name and reverts to
      // available. Works for both stock builds and non-stock builds —
      // a sold-pending-pickup trailer is both.
      final newName = _customerController.text.trim();
      final origName = t.customer?.name ?? t.soldToName ?? '';
      if (newName != origName) {
        payload['soldToName'] = newName;
        // The typed name is now the source of truth — drop any legacy
        // customer-record link so it can't shadow the new name.
        if (t.customerId != null) payload['customerId'] = null;
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
          ? l.editTrailerUpdated(soNumber)
          : l.editTrailerUpdatedPdfWarn(pdfWarning);

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
        _errorMessage = l.editTrailerFail;
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
    final l = AppLocalizations.of(context);
    try {
      final result = await storageRepo.uploadFile(
        fileType: 'so_pdf',
        trailerId: trailerId,
        fileName: file.name,
        bytes: file.bytes!,
        contentType: 'application/pdf',
      );
      if (result.queued || result.storageKey == null) {
        return l.createTrailerPdfRetryLater;
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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.editTrailerTitle(widget.trailer.soNumber))),
      body: _loadingModels
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _modelOptions.isEmpty
              ? SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 48, color: AppColors.error),
                          const SizedBox(height: 12),
                          Text(
                            _loadModelsError ?? l.createTrailerModelsNone,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loadModels,
                            icon: const Icon(Icons.refresh),
                            label: Text(l.commonRetry),
                          ),
                        ],
                      ),
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
                          decoration: InputDecoration(
                            labelText: l.createTrailerSoLabel,
                            prefixIcon: const Icon(Icons.tag),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? l.createTrailerSoRequired
                              : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: _selectedModelId,
                          decoration: InputDecoration(
                            labelText: l.createTrailerModelLabel,
                            prefixIcon: const Icon(Icons.local_shipping_outlined),
                          ),
                          items: _modelOptions
                              .map((m) => DropdownMenuItem(
                                    value: m.id,
                                    child: Text(m.displayName),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedModelId = v),
                          validator: (v) =>
                              v == null ? l.createTrailerModelRequired : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _colorController,
                          decoration: InputDecoration(
                            labelText: l.createTrailerColorLabel,
                            prefixIcon: const Icon(Icons.palette_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _sizeController,
                          decoration: InputDecoration(
                            labelText: l.createTrailerSizeLabel,
                            prefixIcon: const Icon(Icons.straighten),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: l.createTrailerNotesLabel,
                            prefixIcon: const Padding(
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
                          decoration: InputDecoration(
                            labelText: l.createTrailerSpecialLabel,
                            hintText: l.createTrailerSpecialHint,
                            prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Stock-build toggle is independent of the customer
                        // field — a sold trailer can also sit at a yard until
                        // pickup, and the customer can be added or changed
                        // any time after creation.
                        SwitchListTile(
                          title: Text(l.createTrailerStockBuild),
                          subtitle: Text(l.createTrailerStockBuildSubtitle),
                          value: _isStockBuild,
                          activeColor: AppColors.amber,
                          onChanged: (v) => setState(() {
                            _isStockBuild = v;
                            if (!v) {
                              _selectedStockLocationId = null;
                              _stockLocationError = null;
                            }
                          }),
                          contentPadding: EdgeInsets.zero,
                        ),
                        // Customer name — always visible so a customer can
                        // be added retroactively to a trailer that was
                        // originally created without one (or cleared).
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customerController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: l.createTrailerCustomerLabel,
                            hintText: l.createTrailerCustomerHint,
                            helperText: l.createTrailerCustomerHelper,
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                        if (_isStockBuild) ...[
                          const SizedBox(height: 12),
                          StockLocationChips(
                            labelText: l.createTrailerStockDestLabel,
                            selectedLocationId: _selectedStockLocationId,
                            enabled: !_isSubmitting,
                            onChanged: (loc) => setState(() {
                              _selectedStockLocationId = loc.id;
                              _stockLocationError = null;
                            }),
                            errorText: _stockLocationError,
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
                                      : Text(
                                          l.editTrailerSubmit,
                                          style: const TextStyle(
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
    final l = AppLocalizations.of(context);
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
              Expanded(
                child: Text(
                  l.createTrailerPdfSectionTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (hasNew)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: l.editTrailerPdfDiscardTooltip,
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
            Text(
              l.editTrailerPdfExisting,
              style: const TextStyle(fontSize: 12, color: AppColors.disabled),
            )
          else
            Text(
              l.createTrailerPdfOptionalHelper,
              style: const TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(hasNew || hasExisting
                ? l.createTrailerPdfReplace
                : l.createTrailerPdfAttach),
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
