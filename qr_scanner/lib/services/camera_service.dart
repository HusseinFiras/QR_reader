import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:camera_windows/camera_windows.dart';
import 'package:flutter/services.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:camera/camera.dart';

class CameraService with ChangeNotifier {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isStreaming = false;
  bool _isDisposing = false;
  bool _isStarting = false;
  Timer? _captureTimer;
  final StreamController<Uint8List> _frameStreamController = StreamController<Uint8List>.broadcast();
  Completer<void>? _initializationCompleter;
  int _consecutiveErrors = 0;

  Stream<Uint8List> get frameStream => _frameStreamController.stream;
  bool get isInitialized => _isInitialized;
  bool get isStreaming => _isStreaming;
  List<CameraDescription> get cameras => _cameras;
  CameraController? get controller => _controller;

  Future<void> _waitForInitialization() async {
    if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
      debugPrint('CameraService: Waiting for ongoing initialization...');
      try {
        await _initializationCompleter!.future;
      } catch (e) {
        debugPrint('CameraService: Error during waiting: $e');
      }
    }
  }

  Future<void> initialize() async {
    debugPrint('CameraService: Initializing camera service...');
    try {
      if (_isInitialized) {
        debugPrint('CameraService: Already initialized, skipping...');
        return;
      }

      await _waitForInitialization();

      if (_isStarting) {
        debugPrint('CameraService: Initialization already in progress, waiting...');
        return;
      }

      _isStarting = true;
      _initializationCompleter = Completer<void>();
      
      // Ensure proper cleanup before initialization
      await cleanupCamera();
      
      // Create a timeout for the entire initialization process
      final timeoutFuture = Future.delayed(const Duration(seconds: 10), () {
        if (_initializationCompleter != null && !_initializationCompleter!.isCompleted) {
          debugPrint('CameraService: Initialization timed out after 10 seconds');
          return Future.error('Camera initialization timed out');
        }
      });
      
      // Register the Windows camera plugin
      debugPrint('CameraService: Registering Windows camera plugin...');
      CameraPlatform.instance = CameraWindows();
      
      debugPrint('CameraService: Getting available cameras...');
      
      // Use a race between the timeout and the actual operation
      await Future.any([
        timeoutFuture,
        Future(() async {
          _cameras = await CameraPlatform.instance.availableCameras();
          debugPrint('CameraService: Found ${_cameras.length} cameras');
          
          if (_cameras.isEmpty) {
            debugPrint('CameraService: No cameras available');
            throw Exception('No cameras available');
          }
        })
      ]);
      
      _isInitialized = true;
      _isStarting = false;
      _initializationCompleter?.complete();
      notifyListeners();
      debugPrint('CameraService: Initialization successful');
    } on PlatformException catch (e) {
      debugPrint('CameraService: PlatformException during initialization: ${e.message}');
      _isInitialized = false;
      _isStarting = false;
      _initializationCompleter?.completeError(e);
      throw Exception('Failed to initialize camera: ${e.message}');
    } catch (e) {
      debugPrint('CameraService: Error during initialization: $e');
      _isInitialized = false;
      _isStarting = false;
      _initializationCompleter?.completeError(e);
      rethrow;
    } finally {
      _initializationCompleter = null;
    }
  }

  Future<void> startCamera(int cameraIndex) async {
    debugPrint('CameraService: Starting camera at index $cameraIndex...');
    if (!_isInitialized || cameraIndex >= _cameras.length) {
      debugPrint('CameraService: Camera not initialized or invalid index');
      throw Exception('Camera not initialized or invalid index');
    }

    await _waitForInitialization();

    if (_isStarting) {
      debugPrint('CameraService: Camera start already in progress, waiting...');
      return;
    }

    _isStarting = true;
    _initializationCompleter = Completer<void>();

    try {
      // Ensure proper cleanup before starting new camera
      await cleanupCamera();
      
      debugPrint('CameraService: Creating new camera controller...');
      
      // Wrap camera creation in a try-catch to handle resource conflict
      try {
        _controller = CameraController(
          _cameras[cameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.bgra8888, // Essential for Windows
        );
      } catch (e) {
        debugPrint('CameraService: Error creating controller: $e');
        if (e.toString().contains('Camera with given device id already exists')) {
          // If we hit this error, perform forced cleanup and retry once
          await _forceCleanupCamera();
          
          // Re-initialize after forced cleanup
          await initialize();
          
          // Retry camera creation after forced cleanup
          if (cameraIndex < _cameras.length) {
            _controller = CameraController(
              _cameras[cameraIndex],
              ResolutionPreset.high,
              enableAudio: false,
              imageFormatGroup: ImageFormatGroup.bgra8888,
            );
          } else {
            throw Exception('Camera index out of range after reinitialization');
          }
        } else {
          // For other errors, just rethrow
          rethrow;
        }
      }

      debugPrint('CameraService: Initializing camera controller...');
      await _controller!.initialize();
      
      _isStarting = false;
      _initializationCompleter?.complete();
      notifyListeners();
      debugPrint('CameraService: Camera started successfully');
    } on CameraException catch (e) {
      debugPrint('CameraService: CameraException during start: ${e.description}');
      await cleanupCamera();
      _isStarting = false;
      _initializationCompleter?.completeError(e);
      throw Exception('Failed to start camera: ${e.description}');
    } catch (e) {
      debugPrint('CameraService: Error during camera start: $e');
      await cleanupCamera();
      _isStarting = false;
      _initializationCompleter?.completeError(e);
      rethrow;
    } finally {
      _initializationCompleter = null;
    }
  }

  void startStreaming() {
    debugPrint('CameraService: Starting image stream...');
    if (_controller == null || _isStreaming) {
      debugPrint('CameraService: Cannot start streaming - controller: ${_controller != null}, isStreaming: $_isStreaming');
      return;
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        debugPrint('CameraService: Using Windows-specific capture implementation');
        _isStreaming = true;
        
        // Use periodic capture instead of streaming
        _captureTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
          if (!_isStreaming || _controller == null) {
            timer.cancel();
            return;
          }
          
          try {
            // Check if controller is still initialized
            if (!_controller!.value.isInitialized) {
              debugPrint('CameraService: Controller no longer initialized, attempting to fix...');
              await _attemptCameraRecovery();
              return;
            }
            
            debugPrint('CameraService: Capturing frame...');
            final image = await _controller!.takePicture();
            final bytes = await image.readAsBytes();
            debugPrint('CameraService: Frame captured, size: ${bytes.length} bytes');
            if (_frameStreamController.hasListener) {
              _frameStreamController.add(bytes);
            }
            // Reset consecutive errors on successful frame capture
            _consecutiveErrors = 0;
          } catch (e) {
            debugPrint('CameraService: Error capturing frame: $e');
            // If we hit consistent errors, try to recover the camera
            _consecutiveErrors++;
            if (_consecutiveErrors > 3) {
              _consecutiveErrors = 0;
              _attemptCameraRecovery();
            }
          }
        });
        debugPrint('CameraService: Windows capture timer started');
      } else if (defaultTargetPlatform == TargetPlatform.android || 
                 defaultTargetPlatform == TargetPlatform.iOS) {
        debugPrint('CameraService: Using mobile streaming implementation');
        _isStreaming = true;
        _controller!.startImageStream((image) {
          if (_frameStreamController.hasListener) {
          final bytes = image.planes[0].bytes;
          _frameStreamController.add(bytes);
          }
        });
      } else {
        debugPrint('CameraService: Unsupported platform: $defaultTargetPlatform');
        throw UnsupportedError('Camera streaming is not supported on this platform');
      }
      notifyListeners();
      debugPrint('CameraService: Streaming started successfully');
    } catch (e) {
      debugPrint('CameraService: Error starting stream: $e');
      _isStreaming = false;
      throw Exception('Failed to start streaming: $e');
    }
  }

  void stopStreaming() {
    debugPrint('CameraService: Stopping image stream...');
    _isStreaming = false;
    
    if (_captureTimer != null) {
      debugPrint('CameraService: Stopping Windows capture timer');
      _captureTimer!.cancel();
      _captureTimer = null;
    }
    
    if (defaultTargetPlatform == TargetPlatform.android || 
        defaultTargetPlatform == TargetPlatform.iOS) {
      _controller?.stopImageStream();
    }
    
    notifyListeners();
    debugPrint('CameraService: Streaming stopped successfully');
  }

  Future<void> cleanupCamera() async {
    debugPrint('CameraService: Cleaning up camera...');
    if (_isDisposing) {
      debugPrint('CameraService: Already disposing, skipping cleanup');
      return;
    }
    _isDisposing = true;

    try {
      debugPrint('CameraService: Stopping stream...');
      stopStreaming();
      
      final controller = _controller;
      if (controller != null) {
        debugPrint('CameraService: Disposing controller...');
        if (controller.value.isInitialized) {
          await controller.dispose();
        }
        _controller = null;
      }
      
      _isInitialized = false;
      notifyListeners();
      debugPrint('CameraService: Cleanup completed successfully');
    } catch (e) {
      debugPrint('CameraService: Error during cleanup: $e');
    } finally {
      _isDisposing = false;
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('CameraService: Disposing service...');
    try {
      await cleanupCamera();
      await _frameStreamController.close();
      super.dispose();
      debugPrint('CameraService: Service disposed successfully');
    } catch (e) {
      debugPrint('CameraService: Error during disposal: $e');
      throw Exception('Failed to dispose camera: $e');
    }
  }

  Future<void> _attemptCameraRecovery() async {
    debugPrint('CameraService: Attempting to recover camera...');
    // Stop streaming first
    stopStreaming();
    
    try {
      // Clean up existing camera controller
      await cleanupCamera();
      
      // Small delay to ensure resources are released
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Try to initialize again
      await initialize();
      
      // If we have cameras, try to start the first one
      if (_cameras.isNotEmpty) {
        await startCamera(0);
        
        // Start streaming again
        startStreaming();
        
        debugPrint('CameraService: Camera recovery successful');
      } else {
        debugPrint('CameraService: No cameras available after recovery attempt');
      }
    } catch (e) {
      debugPrint('CameraService: Camera recovery failed: $e');
      // Reset the error counter to prevent continuous recovery attempts
      _consecutiveErrors = 0;
      
      // If we get the "Camera already exists" error, try a more aggressive cleanup
      if (e.toString().contains('Camera with given device id already exists')) {
        debugPrint('CameraService: Detected camera resource conflict, attempting deeper cleanup');
        await _forceCleanupCamera();
      }
    }
  }
  
  Future<void> _forceCleanupCamera() async {
    debugPrint('CameraService: Performing forced camera cleanup');
    // Set all state variables to initial values
    _isInitialized = false;
    _isStreaming = false;
    _isDisposing = false;
    _isStarting = false;
    _consecutiveErrors = 0;
    
    // Cancel any active timers
    _captureTimer?.cancel();
    _captureTimer = null;
    
    // Nullify controller reference without calling dispose
    // (since the error indicates it's already disposed elsewhere)
    _controller = null;
    
    // Reset camera list
    _cameras = [];
    
    // Notify any listeners
    notifyListeners();
    
    // Wait longer to ensure system resources are freed
    await Future.delayed(const Duration(seconds: 2));
    
    debugPrint('CameraService: Forced cleanup complete');
  }
} 