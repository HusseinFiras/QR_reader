import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'camera_service.dart';
import 'package:window_manager/window_manager.dart';

class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  final CameraService _cameraService = CameraService();
  bool _isRegistered = false;
  Function()? onExit;

  void initialize() {
    debugPrint('AppLifecycleService: Initializing...');
    if (!_isRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isRegistered = true;
      debugPrint('AppLifecycleService: Successfully registered as observer');
      windowManager.addListener(_WindowListener(this));
    } else {
      debugPrint('AppLifecycleService: Already registered');
    }
  }

  void dispose() {
    debugPrint('AppLifecycleService: Disposing...');
    if (_isRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isRegistered = false;
      debugPrint('AppLifecycleService: Successfully unregistered observer');
    } else {
      debugPrint('AppLifecycleService: Not registered, nothing to dispose');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('AppLifecycleService: Lifecycle state changed to: $state');
    if (defaultTargetPlatform == TargetPlatform.windows) {
      debugPrint('AppLifecycleService: Handling Windows platform lifecycle');
      // Windows-specific lifecycle handling
      switch (state) {
        case AppLifecycleState.detached:
          debugPrint('AppLifecycleService: App detached, stopping camera');
          _cameraService.stopStreaming();
          break;
        case AppLifecycleState.resumed:
          debugPrint('AppLifecycleService: App resumed on Windows');
          _cameraService.startStreaming();
          break;
        default:
          // Don't stop the camera for other states on Windows
          debugPrint('AppLifecycleService: Ignoring state change: $state');
          break;
      }
    } else {
      debugPrint('AppLifecycleService: Handling mobile platform lifecycle');
      // Standard mobile lifecycle handling
      switch (state) {
        case AppLifecycleState.paused:
        case AppLifecycleState.inactive:
        case AppLifecycleState.detached:
          debugPrint('AppLifecycleService: Cleaning up camera for mobile');
          _cameraService.cleanupCamera();
          break;
        case AppLifecycleState.resumed:
          debugPrint('AppLifecycleService: App resumed on mobile');
          // Camera will be reinitialized when the widget rebuilds
          break;
        default:
          debugPrint('AppLifecycleService: Unhandled mobile lifecycle state: $state');
          break;
      }
    }
  }
}

class _WindowListener extends WindowListener {
  final AppLifecycleService _service;

  _WindowListener(this._service);

  @override
  void onWindowClose() {
    debugPrint('Window closing, cleaning up...');
    _service.onExit?.call();
    super.onWindowClose();
  }
} 