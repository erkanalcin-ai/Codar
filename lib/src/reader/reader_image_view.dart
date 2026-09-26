import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'html_blocks.dart';

class ReaderImageView extends StatelessWidget {
  const ReaderImageView({super.key, required this.image, required this.fit});

  final ReaderImage image;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (image.dataFormat != 'rgba8888' ||
        image.pixelWidth <= 0 ||
        image.pixelHeight <= 0 ||
        image.data.length < image.pixelWidth * image.pixelHeight * 4) {
      return Image.memory(
        image.data,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    return _RawReaderImage(image: image, fit: fit);
  }
}

class _RawReaderImage extends StatefulWidget {
  const _RawReaderImage({required this.image, required this.fit});

  final ReaderImage image;
  final BoxFit fit;

  @override
  State<_RawReaderImage> createState() => _RawReaderImageState();
}

class _RawReaderImageState extends State<_RawReaderImage> {
  ui.Image? _decoded;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant _RawReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image.data, widget.image.data) ||
        oldWidget.image.pixelWidth != widget.image.pixelWidth ||
        oldWidget.image.pixelHeight != widget.image.pixelHeight) {
      _decoded?.dispose();
      _decoded = null;
      _decode();
    }
  }

  void _decode() {
    ui.decodeImageFromPixels(
      widget.image.data,
      widget.image.pixelWidth,
      widget.image.pixelHeight,
      ui.PixelFormat.rgba8888,
      (decoded) {
        if (!mounted) {
          decoded.dispose();
          return;
        }
        setState(() => _decoded = decoded);
      },
      rowBytes: widget.image.pixelWidth * 4,
    );
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decoded = _decoded;
    if (decoded == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RawImage(
      image: decoded,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
  }
}
