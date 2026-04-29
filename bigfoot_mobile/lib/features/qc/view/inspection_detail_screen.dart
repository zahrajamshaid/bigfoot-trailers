import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../data/models/qc_inspection.dart';
import '../../../domain/repositories/qc_repository.dart';
import '../viewmodel/qc_viewmodel.dart';

/// Displays a single QC inspection: photos, checklist results, inspector info.
class InspectionDetailScreen extends StatefulWidget {
  final int inspectionId;
  const InspectionDetailScreen({super.key, required this.inspectionId});

  @override
  State<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

class _InspectionDetailScreenState extends State<InspectionDetailScreen> {
  QcInspection? _inspection;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final cubit = QcViewModel(
        repository: context.read<QcRepository>(),
        ws: context.read<WsClient>(),
      );
      final inspection = await cubit.fetchInspection(widget.inspectionId);
      await cubit.close();
      if (mounted) setState(() { _inspection = inspection; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = 'Failed to load inspection'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Inspection #${widget.inspectionId}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _InspectionContent(inspection: _inspection!),
    );
  }
}

class _InspectionContent extends StatelessWidget {
  final QcInspection inspection;
  const _InspectionContent({required this.inspection});

  @override
  Widget build(BuildContext context) {
    final isPassed = inspection.result == 'pass';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Result banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (isPassed ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isPassed ? AppColors.success : AppColors.error,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isPassed ? Icons.check_circle : Icons.cancel,
                  size: 32,
                  color: isPassed ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPassed ? 'PASSED' : 'FAILED',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isPassed ? AppColors.success : AppColors.error,
                      ),
                    ),
                    Text(
                      'Attempt #${inspection.attemptNumber}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Spacer(),
                if (inspection.createdAt != null)
                  Text(
                    _formatDate(inspection.createdAt!),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),

          // Fail notes
          if (!isPassed && inspection.failNotes != null) ...[
            const SizedBox(height: 16),
            const Text('Fail Notes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Text(
                inspection.failNotes!,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ],

          // Photos
          if (inspection.photos != null && inspection.photos!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Photos (${inspection.photos!.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: inspection.photos!.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final photo = inspection.photos![index];
                  return GestureDetector(
                    onTap: () => _showPhotoViewer(context, photo),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: photo.downloadUrl != null
                          ? Image.network(
                              photo.downloadUrl!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _PhotoPlaceholder(index: index),
                            )
                          : _PhotoPlaceholder(index: index),
                    ),
                  );
                },
              ),
            ),
          ],

          // Checklist results
          if (inspection.checklistResults != null &&
              inspection.checklistResults!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Checklist (${inspection.checklistResults!.length} items)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: inspection.checklistResults!.asMap().entries.map((entry) {
                  final index = entry.key;
                  final result = entry.value;
                  return Column(
                    children: [
                      if (index > 0) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              result.passed ? Icons.check_circle : Icons.cancel,
                              size: 20,
                              color: result.passed ? AppColors.success : AppColors.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Item #${result.checklistItemId}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  if (result.note != null && result.note!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        result.note!,
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (result.passed ? AppColors.success : AppColors.error)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                result.passed ? 'PASS' : 'FAIL',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: result.passed ? AppColors.success : AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showPhotoViewer(BuildContext context, QcPhotoInfo photo) {
    if (photo.downloadUrl == null) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.network(photo.downloadUrl!),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final int index;
  const _PhotoPlaceholder({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      color: Colors.grey.shade200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo, color: Colors.grey, size: 32),
          Text('Photo ${index + 1}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
