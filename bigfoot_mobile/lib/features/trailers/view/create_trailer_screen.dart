import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../domain/repositories/storage_repository.dart';
import '../../../domain/repositories/trailer_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/stock_location_chips.dart';
import '../viewmodel/trailers_viewmodel.dart';

class CreateTrailerScreen extends StatefulWidget {
  const CreateTrailerScreen({super.key});

  @override
  State<CreateTrailerScreen> createState() => _CreateTrailerScreenState();
}

class _CreateTrailerScreenState extends State<CreateTrailerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _soController = TextEditingController();
  final _colorController = TextEditingController();
  final _sizeController = TextEditingController();
  final _notesController = TextEditingController();
  final _specialNoteController = TextEditingController();
  final _customerController = TextEditingController();
  int? _selectedModelId;
  bool _isStockBuild = false;
  int? _selectedStockLocationId;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Loaded from API
  List<_ModelOption> _modelOptions = [];
  bool _loadingModels = true;
  String? _loadModelsError;

  // QB SO PDF (optional)
  PlatformFile? _selectedPdf;
  String? _pdfWarning;

  // Inline error for the chip-style stock destination picker (chips aren't a
  // FormField so we render the message ourselves on submit).
  String? _stockLocationError;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    if (mounted) {
      setState(() {
        _loadingModels = true;
        _loadModelsError = null;
      });
    }
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
        setState(() {
          _pdfWarning = l.createTrailerPickPdfFail;
        });
        return;
      }
      setState(() {
        _selectedPdf = file;
        _pdfWarning = null;
      });
    } catch (_) {
      setState(() {
        _pdfWarning = l.createTrailerPickerOpenFail;
      });
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
      final api = context.read<DioClient>();
      final trailerRepo = context.read<TrailerRepository>();
      final storageRepo = context.read<StorageRepository>();

      final response = await api.post<Map<String, dynamic>>(
        ApiEndpoints.trailers,
        data: {
          'soNumber': _soController.text.trim(),
          'trailerModelId': _selectedModelId,
          if (_colorController.text.trim().isNotEmpty)
            'color': _colorController.text.trim(),
          if (_sizeController.text.trim().isNotEmpty)
            'sizeFt': _sizeController.text.trim(),
          if (_notesController.text.trim().isNotEmpty)
            'optionsNotes': _notesController.text.trim(),
          if (_specialNoteController.text.trim().isNotEmpty)
            'specialNote': _specialNoteController.text.trim(),
          if (!_isStockBuild && _customerController.text.trim().isNotEmpty)
            'soldToName': _customerController.text.trim(),
          'isStockBuild': _isStockBuild,
          if (_isStockBuild) 'stockLocationId': _selectedStockLocationId,
        },
        fromJson: (d) => d as Map<String, dynamic>,
      );

      // POST /trailers returns { trailer: {...}, stepsSummary: {...} } —
      // the id lives at data.trailer.id, not data.id.
      final trailerData = response.data?['trailer'] as Map<String, dynamic>?;
      final trailerId = (trailerData?['id'] as num?)?.toInt();
      String? pdfWarning;

      if (trailerId != null && _selectedPdf != null) {
        pdfWarning = await _uploadPdf(
          trailerId: trailerId,
          trailerRepo: trailerRepo,
          storageRepo: storageRepo,
          file: _selectedPdf!,
        );
      }

      if (!mounted) return;

      context.read<TrailersViewModel>().load();

      final message = pdfWarning == null
          ? l.createTrailerCreated(_soController.text.trim())
          : l.createTrailerCreatedPdfWarn(pdfWarning);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: pdfWarning == null ? AppColors.success : AppColors.warning,
        ),
      );
      context.pop();
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.displayMessage;
        _isSubmitting = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = l.createTrailerFail;
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
      // qbSoPdfStorageUrl is stored but never read — the detail screen
      // re-signs a fresh download URL from the storageKey on every open.
      // Sending the key satisfies the @IsNotEmpty server validator without
      // a wasted /storage/presign round trip.
      await trailerRepo.uploadQbPdf(
        trailerId: trailerId,
        storageKey: storageKey,
        storageUrl: storageKey,
      );
      return null;
    } on ApiException catch (e) {
      debugPrint('uploadQbPdf API error: ${e.code} ${e.displayMessage}');
      return e.displayMessage;
    } catch (e, stack) {
      debugPrint('uploadQbPdf unexpected error: $e\n$stack');
      return e.toString();
    }
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.createTrailerTitle)),
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
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_errorMessage!,
                                  style: const TextStyle(color: AppColors.error)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // SO Number
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

                    // Trailer Model
                    DropdownButtonFormField<int>(
                      value: _selectedModelId,
                      decoration: InputDecoration(
                        labelText: l.createTrailerModelLabel,
                        prefixIcon: const Icon(Icons.local_shipping_outlined),
                      ),
                      items: _modelOptions.map((m) {
                        return DropdownMenuItem(
                          value: m.id,
                          child: Row(
                            children: [
                              _SeriesDot(series: m.series),
                              const SizedBox(width: 8),
                              Text(m.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedModelId = v),
                      validator: (v) =>
                          v == null ? l.createTrailerModelRequired : null,
                    ),
                    const SizedBox(height: 16),

                    // Color
                    TextFormField(
                      controller: _colorController,
                      decoration: InputDecoration(
                        labelText: l.createTrailerColorLabel,
                        prefixIcon: const Icon(Icons.palette_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Size
                    TextFormField(
                      controller: _sizeController,
                      decoration: InputDecoration(
                        labelText: l.createTrailerSizeLabel,
                        prefixIcon: const Icon(Icons.straighten),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Options/Notes
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

                    // Special Note (short, single-line free-form)
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

                    // Stock Build toggle
                    SwitchListTile(
                      title: Text(l.createTrailerStockBuild),
                      subtitle: Text(l.createTrailerStockBuildSubtitle),
                      value: _isStockBuild,
                      activeColor: AppColors.amber,
                      onChanged: (v) => setState(() {
                        _isStockBuild = v;
                        if (v) {
                          _customerController.clear();
                        } else {
                          _selectedStockLocationId = null;
                        }
                      }),
                      contentPadding: EdgeInsets.zero,
                    ),

                    // Customer name — only when not a stock build. Plain text:
                    // customer records are owned by the GoHighLevel integration.
                    if (!_isStockBuild) ...[
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
                    ],
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

                    // QB SO PDF attachment
                    _PdfPickerTile(
                      selectedFile: _selectedPdf,
                      onPick: _isSubmitting ? null : _pickPdf,
                      onClear: _isSubmitting
                          ? null
                          : () => setState(() => _selectedPdf = null),
                      warning: _pdfWarning,
                    ),
                    const SizedBox(height: 24),

                    // Submit
                    Builder(
                      builder: (context) {
                        final safeBottom = MediaQuery.of(context).viewPadding.bottom;
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
                                          strokeWidth: 2.5, color: AppColors.white),
                                    )
                                  : Text(l.createTrailerSubmit,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w600)),
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
  const _ModelOption({required this.id, required this.displayName, required this.series});
}

class _PdfPickerTile extends StatelessWidget {
  final PlatformFile? selectedFile;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final String? warning;

  const _PdfPickerTile({
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
    final hasFile = selectedFile != null;
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
              if (hasFile)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: l.createTrailerPdfRemoveTooltip,
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (hasFile) ...[
            Text(
              selectedFile!.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _formatSize(selectedFile!.size),
              style: const TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          ] else
            Text(
              l.createTrailerPdfOptionalHelper,
              style: const TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(hasFile
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

class _SeriesDot extends StatelessWidget {
  final String series;
  const _SeriesDot({required this.series});

  @override
  Widget build(BuildContext context) {
    final color = switch (series) {
      'xp' => AppColors.seriesXp,
      'yeti' => AppColors.seriesYeti,
      'deck_over' => AppColors.seriesDeckOver,
      'gooseneck_dump' => AppColors.seriesGooseneck,
      _ => AppColors.disabled,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
