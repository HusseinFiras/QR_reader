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
  bool _wasStreaming = false;
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
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          debugPrint('AppLifecycleService: App paused/inactive/detached, saving state and stopping camera');
          _wasStreaming = _cameraService.isStreaming;
          _cameraService.stopStreaming();
          // Also perform full cleanup to ensure camera resources are released
          _cameraService.cleanupCamera();
          break;
        case AppLifecycleState.resumed:
          debugPrint('AppLifecycleService: App resumed on Windows');
          // Add delay to ensure the app is fully visible before restarting camera
          Future.delayed(const Duration(milliseconds: 500), () async {
            if (_wasStreaming) {
              debugPrint('AppLifecycleService: Restoring camera after resume');
              try {
                await _cameraService.initialize();
                if (_cameraService.cameras.isNotEmpty) {
                  await _cameraService.startCamera(0);
                  _cameraService.startStreaming();
                }
              } catch (e) {
                debugPrint('AppLifecycleService: Error restoring camera: $e');
              }
            }
          });
          break;
        default:
          // Handle future AppLifecycleState values
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