import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';
import 'dart:async';

class CameraPreviewWidget extends StatefulWidget {
  final CameraService cameraService;
  final Function(Uint8List) onFrameCaptured;

  const CameraPreviewWidget({
    Key? key,
    required this.cameraService,
    required this.onFrameCaptured,
  }) : super(key: key);

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  Uint8List? _lastFrame;
  StreamSubscription<Uint8List>? _frameSubscription;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // Listen to frame stream for Windows
      _frameSubscription = widget.cameraService.frameStream.listen((frame) {
        if (!mounted) return;
        setState(() {
          _lastFrame = frame;
        });
        widget.onFrameCaptured(frame);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (_lastFrame == null) {
        return const Center(child: Text('Waiting for camera frame...'));
      }
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Image.memory(
          _lastFrame!,
          gaplessPlayback: true,
          fit: BoxFit.cover,
        ),
      );
    } else {
      // Mobile platforms use standard CameraPreview
      final previewSize = controller.value.previewSize;
      if (previewSize == null) {
        return const Center(child: Text('Camera preview size is not available'));
      }

      return AspectRatio(
        aspectRatio: previewSize.width / previewSize.height,
        child: CameraPreview(controller),
      );
    }
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    super.dispose();
  }
} 