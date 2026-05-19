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
        setState(() {
          _pdfWarning = 'Could not read the selected PDF file.';
        });
        return;
      }
      setState(() {
        _selectedPdf = file;
        _pdfWarning = null;
      });
    } catch (_) {
      setState(() {
        _pdfWarning = 'Unable to open the file picker.';
      });
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
          ? 'Trailer ${_soController.text.trim()} created with 12 workflow steps'
          : 'Trailer created. PDF upload failed: $pdfWarning';

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
        _errorMessage = 'Failed to create trailer';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create Trailer')),
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
                      decoration: const InputDecoration(
                        labelText: 'SO Number *',
                        prefixIcon: Icon(Icons.tag),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'SO number is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Trailer Model
                    DropdownButtonFormField<int>(
                      value: _selectedModelId,
                      decoration: const InputDecoration(
                        labelText: 'Trailer Model *',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
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
                      validator: (v) => v == null ? 'Select a trailer model' : null,
                    ),
                    const SizedBox(height: 16),

                    // Color
                    TextFormField(
                      controller: _colorController,
                      decoration: const InputDecoration(
                        labelText: 'Color',
                        prefixIcon: Icon(Icons.palette_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Size
                    TextFormField(
                      controller: _sizeController,
                      decoration: const InputDecoration(
                        labelText: 'Size (ft)',
                        prefixIcon: Icon(Icons.straighten),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Options/Notes
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

                    // Special Note (short, single-line free-form)
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

                    // Stock Build toggle
                    SwitchListTile(
                      title: const Text('Stock Build'),
                      subtitle: const Text('No customer assigned'),
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
                        decoration: const InputDecoration(
                          labelText: 'Customer',
                          hintText: 'Buyer name — leave blank for stock',
                          helperText:
                              'Optional. A trailer with a customer is marked sold.',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                    ],
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
                                  : const Text('Create Trailer',
                                      style: TextStyle(
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
              const Expanded(
                child: Text(
                  'QB Sales Order PDF',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (hasFile)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Remove PDF',
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
            const Text(
              'Optional — attach the QuickBooks SO PDF for this trailer.',
              style: TextStyle(fontSize: 12, color: AppColors.disabled),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(hasFile ? 'Replace PDF' : 'Attach PDF'),
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
