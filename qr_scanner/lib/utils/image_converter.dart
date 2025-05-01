import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class ImageConverter {
  static Uint8List? convertCameraImage(CameraImage image) {
    try {
      // For Windows BGRA format
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        return allBytes.done().buffer.asUint8List();
      }
      return null;
    } catch (e) {
      debugPrint('Error converting image: $e');
      return null;
    }
  }
} 