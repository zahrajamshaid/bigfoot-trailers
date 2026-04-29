import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_colors.dart';

class ImageViewerScreen extends StatefulWidget {
  final List<Uint8List> images;
  final List<String> fileNames;
  final int initialIndex;

  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.fileNames,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.fileNames[_index]),
        actions: [
          IconButton(
            onPressed: () => _shareCurrent(),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: PhotoViewGallery.builder(
        pageController: _controller,
        itemCount: widget.images.length,
        onPageChanged: (value) => setState(() => _index = value),
        builder: (context, index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: MemoryImage(widget.images[index]),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2.5,
          );
        },
        loadingBuilder: (_, __) => const Center(
          child: CircularProgressIndicator(color: AppColors.amber),
        ),
      ),
    );
  }

  Future<void> _shareCurrent() async {
    final file = XFile.fromData(
      widget.images[_index],
      name: widget.fileNames[_index],
      mimeType: 'image/jpeg',
    );
    await SharePlus.instance.share(ShareParams(files: [file]));
  }
}
