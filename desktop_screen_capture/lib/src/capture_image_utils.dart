import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CroppedImageResult {
  final Uint8List imageBytes;
  final Size size;

  const CroppedImageResult({required this.imageBytes, required this.size});
}

class CaptureImageUtils {
  static Future<CroppedImageResult?> cropPngBytes({
    required Uint8List imageBytes,
    required Rect selectionRect,
    Size? sourceSize,
  }) async {
    final image = await _decodeImage(imageBytes);
    ui.Picture? picture;
    ui.Image? croppedImage;
    try {
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final cropRect = scaleSelectionToImage(
        selectionRect: selectionRect,
        sourceSize: sourceSize ?? imageSize,
        imageSize: imageSize,
      );

      if (cropRect.width < 1 || cropRect.height < 1) {
        return null;
      }

      final outputWidth = cropRect.width.round();
      final outputHeight = cropRect.height.round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final destinationRect = Rect.fromLTWH(
        0,
        0,
        outputWidth.toDouble(),
        outputHeight.toDouble(),
      );

      canvas.drawImageRect(image, cropRect, destinationRect, Paint());

      picture = recorder.endRecording();
      croppedImage = await picture.toImage(outputWidth, outputHeight);
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return null;

      return CroppedImageResult(
        imageBytes: bytes,
        size: Size(outputWidth.toDouble(), outputHeight.toDouble()),
      );
    } finally {
      croppedImage?.dispose();
      picture?.dispose();
      image.dispose();
    }
  }

  static Rect scaleSelectionToImage({
    required Rect selectionRect,
    required Size sourceSize,
    required Size imageSize,
  }) {
    if (!_isUsableSize(sourceSize) || !_isUsableSize(imageSize)) {
      return Rect.zero;
    }

    final normalizedRect = Rect.fromLTRB(
      math.min(selectionRect.left, selectionRect.right),
      math.min(selectionRect.top, selectionRect.bottom),
      math.max(selectionRect.left, selectionRect.right),
      math.max(selectionRect.top, selectionRect.bottom),
    );
    if (!_isFiniteRect(normalizedRect)) {
      return Rect.zero;
    }

    final scaleX = imageSize.width / sourceSize.width;
    final scaleY = imageSize.height / sourceSize.height;
    final scaledRect = Rect.fromLTRB(
      normalizedRect.left * scaleX,
      normalizedRect.top * scaleY,
      normalizedRect.right * scaleX,
      normalizedRect.bottom * scaleY,
    );
    if (!_isFiniteRect(scaledRect)) {
      return Rect.zero;
    }

    final left = _clampDouble(
      scaledRect.left.floorToDouble(),
      0,
      imageSize.width,
    );
    final top = _clampDouble(
      scaledRect.top.floorToDouble(),
      0,
      imageSize.height,
    );
    final right = _clampDouble(
      scaledRect.right.ceilToDouble(),
      0,
      imageSize.width,
    );
    final bottom = _clampDouble(
      scaledRect.bottom.ceilToDouble(),
      0,
      imageSize.height,
    );

    if (right <= left || bottom <= top) {
      return Rect.zero;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static double _clampDouble(double value, double min, double max) {
    return math.max(min, math.min(value, max));
  }

  static bool _isUsableSize(Size size) {
    return size.width.isFinite &&
        size.height.isFinite &&
        size.width > 0 &&
        size.height > 0;
  }

  static bool _isFiniteRect(Rect rect) {
    return rect.left.isFinite &&
        rect.top.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite;
  }
}
