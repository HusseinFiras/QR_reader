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

  // Manual entry controllers
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  DateTime? _selectedDateTime;
  bool _qrCooldown = false;

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
    _numberController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _notesController.dispose();
    super.dispose();
    debugPrint('HomeScreen: Disposed successfully');
  }

  void _handleQRResult(String qrValue, DateTime timestamp) {
    setState(() {
      _numberController.text = qrValue;
      _selectedDateTime = timestamp;
      _dateController.text = _formatDate(timestamp);
      _timeController.text = _formatTime(timestamp);
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

  String _formatDate(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }
  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _pickDate() async {
    final now = _selectedDateTime ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year, picked.month, picked.day,
          _selectedDateTime?.hour ?? now.hour,
          _selectedDateTime?.minute ?? now.minute,
        );
        _dateController.text = _formatDate(_selectedDateTime!);
      });
    }
  }

  Future<void> _pickTime() async {
    final now = _selectedDateTime ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now.hour, minute: now.minute),
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime?.year ?? now.year,
          _selectedDateTime?.month ?? now.month,
          _selectedDateTime?.day ?? now.day,
          picked.hour,
          picked.minute,
        );
        _timeController.text = _formatTime(_selectedDateTime!);
      });
    }
  }

  void _onQRDetected(QRResult qr) {
    if (_qrCooldown || qr.data == _lastQRResult) return;
    _lastQRResult = qr.data;
    _qrCooldown = true;
    _handleQRResult(qr.data, qr.timestamp);
    Future.delayed(const Duration(seconds: 2), () {
      _qrCooldown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF181B20),
        appBar: AppBar(
          backgroundColor: const Color(0xFF181B20),
          elevation: 0,
          title: const Text(
            'تسجيل الدوام',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Row(
          children: [
            // Sidebar
            Container(
              width: 90,
              color: const Color(0xFF23262B),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  _SidebarItem(
                    icon: Icons.dashboard,
                    label: 'لوحة التحكم',
                    selected: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.group,
                    label: 'المقاتلين',
                    selected: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.qr_code,
                    label: 'الدوام',
                    selected: true,
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.bar_chart,
                    label: 'التقارير',
                    selected: false,
                    onTap: () {},
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.settings,
                    label: 'الاعدادات',
                    selected: false,
                    onTap: () {},
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // QR Scanner Panel
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF23262B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'ماسح رمز QR',
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      StreamBuilder<QRResult>(
                                        stream: _backendService.resultStream,
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData && snapshot.data != null) {
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              _onQRDetected(snapshot.data!);
                                            });
                                          }
                                          return CameraPreviewWidget(
                                            cameraService: _cameraService,
                                            onFrameCaptured: _handleFrameCaptured,
                                          );
                                        },
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
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Manual Entry Panel
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF23262B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'إدخال يدوي',
                              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _numberController,
                              decoration: InputDecoration(
                                labelText: 'رقم المقاتل',
                                labelStyle: const TextStyle(color: Colors.white70),
                                filled: true,
                                fillColor: const Color(0xFF181B20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _dateController,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'التاريخ',
                                      labelStyle: const TextStyle(color: Colors.white70),
                                      filled: true,
                                      fillColor: const Color(0xFF181B20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.right,
                                    onTap: _pickDate,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _timeController,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'الوقت',
                                      labelStyle: const TextStyle(color: Colors.white70),
                                      filled: true,
                                      fillColor: const Color(0xFF181B20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.right,
                                    onTap: _pickTime,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _notesController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'ملاحظات',
                                labelStyle: const TextStyle(color: Colors.white70),
                                filled: true,
                                fillColor: const Color(0xFF181B20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.right,
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF90B4FF),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.login),
                                    label: const Text('تسجيل حضور يدوي'),
                                    onPressed: () {},
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF90B4FF),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.logout),
                                    label: const Text('تسجيل انصراف يدوي'),
                                    onPressed: () {},
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sidebar item widget
class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF181B20) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? const Color(0xFF90B4FF) : Colors.white, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFF90B4FF) : Colors.white,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 