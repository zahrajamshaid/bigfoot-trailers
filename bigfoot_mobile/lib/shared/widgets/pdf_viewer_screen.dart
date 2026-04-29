import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';
import '../../domain/repositories/storage_repository.dart';

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
              ? Center(child: Text('Failed to load PDF: $_error'))
              : PDFView(
                  filePath: _file!.path,
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: true,
                  pageFling: true,
                ),
    );
  }

  Future<void> _share() async {
    if (_file == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(_file!.path)]));
  }
}
