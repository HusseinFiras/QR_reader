import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/camera_service.dart';
import '../services/backend_service.dart';
import '../services/scanner_performance_service.dart';
import '../utils/image_converter.dart';
import '../widgets/camera_preview_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CameraService _cameraService;
  late BackendService _backendService;
  final ScannerPerformanceService _performanceService = ScannerPerformanceService();
  String? _lastQRResult;
  String? _errorMessage;
  bool _showSuccessAnimation = false;

  @override
  void initState() {
    debugPrint('HomeScreen: Initializing state...');
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    debugPrint('HomeScreen: Initializing services...');
    try {
      // Initialize services
      _cameraService = Provider.of<CameraService>(context, listen: false);
      _backendService = Provider.of<BackendService>(context, listen: false);
      debugPrint('HomeScreen: Services obtained from Provider');

      // Connect to backend first
      debugPrint('HomeScreen: Connecting to backend...');
      await _backendService.connect();
      debugPrint('HomeScreen: Backend connected successfully');
      
      // Then initialize camera
      debugPrint('HomeScreen: Initializing camera...');
      await _cameraService.initialize();
      await _cameraService.startCamera(0);
      debugPrint('HomeScreen: Camera initialized successfully');
      
      if (mounted) {
        debugPrint('HomeScreen: Starting camera stream...');
        _cameraService.startStreaming();
        debugPrint('HomeScreen: Camera stream started successfully');
      }
    } catch (e) {
      debugPrint('HomeScreen: Error during service initialization: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error initializing services: $e';
        });
      }
    }
  }

  void _handleFrameCaptured(Uint8List frameData) async {
    debugPrint('HomeScreen: Frame captured, processing...');
    final stopwatch = Stopwatch()..start();
    
    try {
      // Process QR code here
      debugPrint('HomeScreen: Sending frame to backend...');
      await _backendService.sendFrame(frameData);
      debugPrint('HomeScreen: Frame sent successfully');
    } catch (e) {
      debugPrint('HomeScreen: Error processing QR image: $e');
    } finally {
      stopwatch.stop();
      _performanceService.recordFrameProcessed(stopwatch.elapsed);
      debugPrint('HomeScreen: Frame processing completed in ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  @override
  void dispose() {
    debugPrint('HomeScreen: Disposing...');
    _cameraService.stopStreaming();
    _cameraService.dispose();
    _backendService.disconnect();
    super.dispose();
    debugPrint('HomeScreen: Disposed successfully');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () {
              _performanceService.logPerformanceMetrics();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CameraPreviewWidget(
                  cameraService: _cameraService,
                  onFrameCaptured: _handleFrameCaptured,
                ),
                if (_errorMessage != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.black54,
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                if (_showSuccessAnimation)
                  Positioned.fill(
                    child: Container(
                      color: Colors.green.withOpacity(0.3),
                      child: const Center(
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 100,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                StreamBuilder<QRResult>(
                  stream: _backendService.resultStream,
                  builder: (context, snapshot) {
                    debugPrint('HomeScreen: StreamBuilder update - hasData: ${snapshot.hasData}');
                    
                    if (snapshot.hasData && snapshot.data != null) {
                      final qrData = snapshot.data!.data;
                      debugPrint('HomeScreen: Received QR result: $qrData');
                      
                      // Only update if the QR code is different
                      if (_lastQRResult != qrData) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _lastQRResult = qrData;
                              _showSuccessAnimation = true;
                            });
                            
                            Future.delayed(const Duration(milliseconds: 1000), () {
                              if (mounted) {
                                setState(() {
                                  _showSuccessAnimation = false;
                                });
                              }
                            });
                          }
                        });
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Last Scanned QR Code:',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.grey[100],
                          ),
                          child: SelectableText(
                            _lastQRResult ?? 'No QR code detected',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: _lastQRResult != null ? Colors.black : Colors.grey,
                              fontWeight: _lastQRResult != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 