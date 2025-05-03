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
      
      // Register the Windows camera plugin
      debugPrint('CameraService: Registering Windows camera plugin...');
      CameraPlatform.instance = CameraWindows();
      
      debugPrint('CameraService: Getting available cameras...');
      _cameras = await CameraPlatform.instance.availableCameras();
      debugPrint('CameraService: Found ${_cameras.length} cameras');
      
      if (_cameras.isEmpty) {
        debugPrint('CameraService: No cameras available');
        throw Exception('No cameras available');
      }
      
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
      _controller = CameraController(
        _cameras[cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888, // Essential for Windows
      );

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
            debugPrint('CameraService: Capturing frame...');
            final image = await _controller!.takePicture();
            final bytes = await image.readAsBytes();
            debugPrint('CameraService: Frame captured, size: ${bytes.length} bytes');
            if (_frameStreamController.hasListener) {
            _frameStreamController.add(bytes);
            }
          } catch (e) {
            debugPrint('CameraService: Error capturing frame: $e');
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
} 