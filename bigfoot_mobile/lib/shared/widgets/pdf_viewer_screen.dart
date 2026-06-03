import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/platform/platform_support.dart';
import '../../domain/repositories/storage_repository.dart';
import '../../l10n/generated/app_localizations.dart';

class PdfViewerArgs {
  final String storageKey;
  final String title;

  const PdfViewerArgs({required this.storageKey, required this.title});
}

class PdfViewerScreen extends StatefulWidget {
  final PdfViewerArgs args;

  const PdfViewerScreen({super.key, required this.args});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  File? _file;
  bool _loading = true;
  String? _error;

  StorageRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repository ??= context.read<StorageRepository>();
    if (_file == null && _loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = _repository;
      if (repo == null) return;
      final file = await repo.downloadToTempFile(
        widget.args.storageKey,
        fileName: '${widget.args.title}.pdf',
      );
      if (!mounted) return;
      setState(() => _file = file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.args.title),
        actions: [
          IconButton(
            onPressed: _file == null ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : _error != null
              ? Center(child: Text('${AppLocalizations.of(context).pdfViewerLoadFail}: $_error'))
              : PlatformSupport.supportsInAppPdfView
                  ? PDFView(
                      filePath: _file!.path,
                      enableSwipe: true,
                      swipeHorizontal: false,
                      autoSpacing: true,
                      pageFling: true,
                    )
                  : _DesktopPdfPlaceholder(file: _file!),
    );
  }

  Future<void> _share() async {
    if (_file == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(_file!.path)]));
  }
}

/// Desktop fallback: flutter_pdfview ships no Windows/macOS/Linux native view,
/// so we hand the file off to the OS default PDF reader (Edge, Adobe, Preview)
/// via the same temp-file path the mobile viewer would render.
class _DesktopPdfPlaceholder extends StatefulWidget {
  final File file;
  const _DesktopPdfPlaceholder({required this.file});

  @override
  State<_DesktopPdfPlaceholder> createState() => _DesktopPdfPlaceholderState();
}

class _DesktopPdfPlaceholderState extends State<_DesktopPdfPlaceholder> {
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openExternal());
  }

  Future<void> _openExternal() async {
    if (_autoOpened) return;
    _autoOpened = true;
    final uri = Uri.file(widget.file.path);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The reopen button below lets the user retry if this raced.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined,
                size: 64, color: AppColors.navy),
            const SizedBox(height: 16),
            const Text(
              'PDF opened in your default reader',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              widget.file.path,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                _autoOpened = false;
                _openExternal();
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Reopen'),
            ),
          ],
        ),
      ),
    );
  }
}
