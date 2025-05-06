import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/camera_service.dart';
import '../services/backend_service.dart';
import '../services/scanner_performance_service.dart';
import '../services/database_service.dart';
import '../utils/image_converter.dart';
import '../widgets/camera_preview_widget.dart';
import 'fighters_screen.dart';
import 'dashboard_screen.dart';
import 'reports_screen.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:math' as math;
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  final String initialPage;
  
  const HomeScreen({Key? key, this.initialPage = 'attendance'}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late CameraService _cameraService;
  late BackendService _backendService;
  final ScannerPerformanceService _performanceService = ScannerPerformanceService();
  String? _lastQRResult;
  String? _errorMessage;
  bool _showSuccessAnimation = false;
  bool _showErrorQrAnimation = false;
  bool _isInitializing = false;
  
  // Animation controllers
  late AnimationController _scanAnimationController;
  late Animation<double> _scanAnimation;

  // Manual entry controllers
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _idController = TextEditingController();

  DateTime? _selectedDateTime;
  bool _qrCooldown = false;

  // Add this for page switching
  late String selectedPage;
  
  // List to hold recent attendance records
  List<Map<String, dynamic>> _recentAttendance = [];
  
  @override
  void initState() {
    debugPrint('HomeScreen: Initializing state...');
    super.initState();
    selectedPage = widget.initialPage;
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize scan animation
    _scanAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scanAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _initializeServices();
    _loadRecentAttendance();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('HomeScreen: AppLifecycleState changed to $state');
    // Don't attempt to handle lifecycle changes here - defer to AppLifecycleService
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (selectedPage == 'dashboard') {
      _initializeServices();
    }
  }

  Future<void> _initializeServices() async {
    // Prevent multiple initialization attempts
    if (_isInitializing) {
      debugPrint('HomeScreen: Services already initializing, skipping...');
      return;
    }
    
    debugPrint('HomeScreen: Initializing services...');
    _isInitializing = true;
    
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
      await Future.delayed(const Duration(milliseconds: 500)); // Add small delay
      await _cameraService.startCamera(0);
      debugPrint('HomeScreen: Camera initialized successfully');
      
      if (mounted && selectedPage == 'attendance') {
        debugPrint('HomeScreen: Starting camera stream...');
        _cameraService.startStreaming();
        debugPrint('HomeScreen: Camera stream started successfully');
        
        // Clear any error message if camera initialized successfully
        setState(() {
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen: Error during service initialization: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error initializing services: $e';
        });
      }
    } finally {
      _isInitializing = false;
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
    WidgetsBinding.instance.removeObserver(this);
    if (selectedPage == 'attendance') {
      _cameraService.stopStreaming();
      _cameraService.cleanupCamera();
      _backendService.disconnect();
    }
    _numberController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _notesController.dispose();
    _nameController.dispose();
    _departmentController.dispose();
    _idController.dispose();
    _scanAnimationController.dispose();
    super.dispose();
    debugPrint('HomeScreen: Disposed successfully');
  }

  Future<void> _loadRecentAttendance() async {
    if (mounted) {
      final databaseService = Provider.of<DatabaseService>(context, listen: false);
      
      // Get today's date in YYYY-MM-DD format
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      try {
        // Load today's attendance records, limit to most recent 5
        final records = await databaseService.getAttendanceByDate(today);
        
        setState(() {
          _recentAttendance = records.isEmpty ? [] : 
              records.sublist(0, records.length > 5 ? 5 : records.length)
                  .cast<Map<String, dynamic>>();
        });
      } catch (e) {
        debugPrint('Error loading recent attendance: $e');
      }
    }
  }
  
  // Reload recent attendance after successful QR scan
  void _reloadRecentAttendance() {
    _loadRecentAttendance();
  }

  void _handleQRResult(Map<String, dynamic> fighter, DateTime timestamp) async {
    // Get backend service for sound
    final backendService = Provider.of<BackendService>(context, listen: false);
    
    // Play success sound
    await backendService.soundService.playQRDetectedSound();
    
    setState(() {
      // Display fighter details in separate fields
      _idController.text = fighter[DatabaseService.columnId]?.toString() ?? '';
      _nameController.text = fighter[DatabaseService.columnName] ?? '';
      _numberController.text = fighter[DatabaseService.columnNumber] ?? '';
      _departmentController.text = fighter[DatabaseService.columnDepartment] ?? '';
      
      _selectedDateTime = timestamp;
      _dateController.text = _formatDate(timestamp);
      _timeController.text = _formatTime(timestamp);
      
      // Leave notes field empty for user to add comments if needed
      _notesController.text = '';
      
      _showSuccessAnimation = true;
      _showErrorQrAnimation = false;
    });
    
    // Reload recent attendance after a short delay
    Future.delayed(const Duration(milliseconds: 1000), () {
      _reloadRecentAttendance();
    });
    
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _showSuccessAnimation = false;
        });
      }
    });
  }

  void _showErrorAnimation(String errorMessage) {
    setState(() {
      _idController.clear();
      _nameController.clear();
      _numberController.clear();
      _departmentController.clear();
      _notesController.text = errorMessage;
      _showErrorQrAnimation = true;
      _showSuccessAnimation = false;
    });
    
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _showErrorQrAnimation = false;
        });
      }
    });
  }

  String _formatDate(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }
  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final period = dt.hour >= 12 ? 'م' : 'ص';
    return "${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period";
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

  void _onQRDetected(QRResult qr) async {
    if (_qrCooldown || qr.data == _lastQRResult) return;
    _lastQRResult = qr.data;
    _qrCooldown = true;
    
    // Get database service
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final backendService = Provider.of<BackendService>(context, listen: false);
    
    try {
      // Lookup fighter in database by QR code
      final fighter = await databaseService.getFighterByQrCode(qr.data);
      
      if (fighter != null) {
        // Fighter found - display details and play success sound
        _handleQRResult(fighter, qr.timestamp);
      } else {
        // No matching fighter found - show error and play error sound
        _showErrorAnimation('رمز QR غير صالح - المقاتل غير مسجل');
        await backendService.soundService.playErrorSound();
      }
    } catch (e) {
      // Database error
      _showErrorAnimation('خطأ في قراءة بيانات المقاتل: $e');
      await backendService.soundService.playErrorSound();
    }
    
    Future.delayed(const Duration(seconds: 2), () {
      _qrCooldown = false;
    });
  }

  void _onSidebarItemTap(String page) {
    if (selectedPage == page) return;
    
    // If we're leaving the attendance screen, clean up camera resources
    if (selectedPage == 'attendance' && page != 'attendance') {
      _cameraService.stopStreaming();
      _cameraService.cleanupCamera();
    }
    
    // If we're entering the attendance screen, initialize camera
    if (page == 'attendance' && selectedPage != 'attendance') {
      _initializeServices();
    }
    
    setState(() {
      selectedPage = page;
    });
  }

  void _showDatabaseInfoDialog(BuildContext context) async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    final dbPath = await DatabaseService.getDatabasePath();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'معلومات قاعدة البيانات',
          style: TextStyle(color: Color(0xFF4D5D44)),
          textAlign: TextAlign.right,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Directionality(
              textDirection: TextDirection.rtl,
              child: const Text(
                'مسار قاعدة البيانات:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4D5D44),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dbPath,
                        style: const TextStyle(color: Colors.black87),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFF4D5D44)),
                      tooltip: 'نسخ المسار',
                      onPressed: () {
                        // Copy path to clipboard
                        Clipboard.setData(ClipboardData(text: dbPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم نسخ المسار'),
                            backgroundColor: Color(0xFF4D5D44),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4D5D44),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                // Open the database directory in explorer
                final dbDir = path.dirname(dbPath);
                Process.run('explorer.exe', [dbDir]);
              },
              child: const Text('فتح مجلد قاعدة البيانات'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Color(0xFF4D5D44))),
          ),
        ],
      ),
    );
  }

  void _recordAttendance(String attendanceType) async {
    // Validate fighter number
    if (_numberController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رقم المقاتل أو مسح رمز QR')),
      );
      return;
    }
    
    // Validate date and time
    if (_selectedDateTime == null) {
      setState(() {
        _selectedDateTime = DateTime.now();
        _dateController.text = _formatDate(_selectedDateTime!);
        _timeController.text = _formatTime(_selectedDateTime!);
      });
    }
    
    // Get database service
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    
    try {
      // Try to find fighter by number
      final fighterList = await databaseService.database.then((db) => 
        db.query(
          DatabaseService.tableFighters,
          where: '${DatabaseService.columnNumber} = ?',
          whereArgs: [_numberController.text],
        )
      );
      
      Map<String, dynamic>? fighter;
      
      if (fighterList.isNotEmpty) {
        fighter = fighterList.first;
      }
      
      if (fighter == null) {
        // Try to find by QR code if not found by number
        fighter = await databaseService.getFighterByQrCode(_numberController.text);
      }
      
      if (fighter == null && _idController.text.isNotEmpty) {
        // Try to find by ID if available
        final int? fighterId = int.tryParse(_idController.text);
        if (fighterId != null) {
          fighter = await databaseService.getFighter(fighterId);
        }
      }
      
      if (fighter == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على المقاتل. تأكد من الرقم أو رمز QR')),
        );
        return;
      }
      
      // Format timestamp
      final timestamp = '${_formatDate(_selectedDateTime!)} ${_formatTime(_selectedDateTime!)}';
      
      // Save attendance record to database
      final attendanceRecord = {
        DatabaseService.columnFighterId: fighter[DatabaseService.columnId],
        DatabaseService.columnTimestamp: timestamp,
        DatabaseService.columnType: attendanceType == 'حضور' 
            ? DatabaseService.typeCheckIn 
            : DatabaseService.typeCheckOut,
        DatabaseService.columnNotes: _notesController.text,
      };
      
      final recordId = await databaseService.recordAttendance(attendanceRecord);
      
      final fighterName = fighter['name'];
      final department = fighter['department'];
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تسجيل $attendanceType للمقاتل: $fighterName ($department)')),
      );
      
      // Show success animation
      setState(() {
        _showSuccessAnimation = true;
      });
      
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _showSuccessAnimation = false;
            
            // Clear the form for next entry if successful
            _idController.clear();
            _nameController.clear();
            _numberController.clear();
            _departmentController.clear();
            _notesController.clear();
          });
        }
      });
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    }
  }

  Widget _buildDashboardContent() {
    return Row(
      children: [
        // QR Scanner Panel
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE0E0E0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4D5D44).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Color(0xFF4D5D44),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'ماسح رمز QR',
                      style: TextStyle(
                        color: Color(0xFF4D5D44), 
                        fontSize: 22, 
                        fontWeight: FontWeight.bold
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Camera preview with rounded corners
                          ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: StreamBuilder<QRResult>(
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
                          ),
                          
                          // Scanner overlay
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFF4D5D44).withOpacity(0.7),
                                  width: 3,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // Top left corner
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                          left: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                        ),
                                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
                                      ),
                                    ),
                                  ),
                                  // Top right corner
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                          right: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                        ),
                                        borderRadius: const BorderRadius.only(topRight: Radius.circular(24)),
                                      ),
                                    ),
                                  ),
                                  // Bottom left corner
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                          left: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                        ),
                                        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24)),
                                      ),
                                    ),
                                  ),
                                  // Bottom right corner
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                          right: BorderSide(color: const Color(0xFF4D5D44), width: 6),
                                        ),
                                        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(24)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          // Scan line animation
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: Container(
                                  width: 250,
                                  height: 250,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: AnimatedBuilder(
                                    animation: _scanAnimation,
                                    builder: (context, child) {
                                      return CustomPaint(
                                        painter: ScanLinePainter(progress: _scanAnimation.value),
                                        child: Container(),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          if (_errorMessage != null && _cameraService.controller?.value.isInitialized != true)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4D5D44),
                                        foregroundColor: Colors.white,
                                        elevation: 4,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _errorMessage = null;
                                        });
                                        _initializeServices();
                                      },
                                      child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 16)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_showSuccessAnimation)
                            Positioned.fill(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 500),
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4D5D44).withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TweenAnimationBuilder<double>(
                                              tween: Tween<double>(begin: 0.5, end: 1.0),
                                              duration: const Duration(milliseconds: 700),
                                              curve: Curves.elasticOut,
                                              builder: (context, scale, child) {
                                                return Transform.scale(
                                                  scale: scale,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(24),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      shape: BoxShape.circle,
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: const Color(0xFF4D5D44).withOpacity(0.5),
                                                          blurRadius: 20,
                                                          spreadRadius: 5,
                                                        ),
                                                      ],
                                                    ),
                                                    child: const Icon(
                                                      Icons.check,
                                                      color: Color(0xFF4D5D44),
                                                      size: 80,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 20),
                                            if (_nameController.text.isNotEmpty)
                                              AnimatedOpacity(
                                                opacity: value,
                                                duration: const Duration(milliseconds: 500),
                                                child: Text(
                                                  _nameController.text,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 24,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            AnimatedOpacity(
                                              opacity: value,
                                              duration: const Duration(milliseconds: 800),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Text(
                                                  'تم تسجيل الحضور بنجاح',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (_showErrorQrAnimation)
                            Positioned.fill(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 500),
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Center(
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween<double>(begin: 0.5, end: 1.0),
                                          duration: const Duration(milliseconds: 700),
                                          curve: Curves.elasticOut,
                                          builder: (context, scale, child) {
                                            return Transform.scale(
                                              scale: scale,
                                              child: Container(
                                                padding: const EdgeInsets.all(24),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.red.withOpacity(0.5),
                                                      blurRadius: 20,
                                                      spreadRadius: 5,
                                                    ),
                                                  ],
                                                ),
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    const Icon(
                                                      Icons.close,
                                                      color: Colors.red,
                                                      size: 80,
                                                    ),
                                                    // Pulsing ring effect
                                                    TweenAnimationBuilder<double>(
                                                      tween: Tween<double>(begin: 0.0, end: 1.0),
                                                      duration: const Duration(milliseconds: 1500),
                                                      curve: Curves.easeInOut,
                                                      builder: (context, pulseValue, _) {
                                                        return Opacity(
                                                          opacity: (1 - pulseValue) * 0.6,
                                                          child: Transform.scale(
                                                            scale: 0.8 + 0.3 * pulseValue,
                                                            child: Container(
                                                              width: 130,
                                                              height: 130,
                                                              decoration: BoxDecoration(
                                                                color: Colors.transparent,
                                                                shape: BoxShape.circle,
                                                                border: Border.all(
                                                                  color: Colors.red,
                                                                  width: 5,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4D5D44).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _cameraService.controller?.value.isInitialized == true ? 
                            Colors.greenAccent : Colors.orangeAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_cameraService.controller?.value.isInitialized == true ? 
                                Colors.greenAccent : Colors.orangeAccent).withOpacity(0.5),
                              blurRadius: 6,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _cameraService.controller?.value.isInitialized == true ? 
                          'الكاميرا جاهزة للمسح' : 'جاري تهيئة الكاميرا...',
                        style: const TextStyle(
                          color: Color(0xFF4D5D44),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE0E0E0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4D5D44).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.edit_document,
                        color: Color(0xFF4D5D44),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'إدخال يدوي',
                      style: TextStyle(
                        color: Color(0xFF4D5D44), 
                        fontSize: 22, 
                        fontWeight: FontWeight.bold
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Fighter ID field
                _buildStyledTextField(
                  controller: _idController,
                  label: 'رقم المقاتل (ID)',
                  icon: Icons.badge,
                  readOnly: true,
                ),
                const SizedBox(height: 16),
                // Fighter name field
                _buildStyledTextField(
                  controller: _nameController,
                  label: 'اسم المقاتل',
                  icon: Icons.person,
                  readOnly: true,
                ),
                const SizedBox(height: 16),
                // Fighter phone number field
                _buildStyledTextField(
                  controller: _numberController,
                  label: 'رقم الهاتف',
                  icon: Icons.phone,
                ),
                const SizedBox(height: 16),
                // Fighter department field
                _buildStyledTextField(
                  controller: _departmentController,
                  label: 'القسم',
                  icon: Icons.business,
                  readOnly: true,
                ),
                const SizedBox(height: 16),
                // Date picker field
                _buildStyledTextField(
                  controller: _dateController,
                  label: 'التاريخ',
                  icon: Icons.calendar_today,
                  readOnly: true,
                  onTap: _pickDate,
                ),
                
                const SizedBox(height: 16),
                // Time picker field
                _buildStyledTextField(
                  controller: _timeController,
                  label: 'الوقت',
                  icon: Icons.access_time,
                  readOnly: true,
                  onTap: _pickTime,
                ),
                const SizedBox(height: 16),
                _buildStyledTextField(
                  controller: _notesController,
                  label: 'ملاحظات',
                  icon: Icons.note,
                  maxLines: 2,
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        label: 'تسجيل حضور',
                        icon: Icons.login,
                        color: const Color(0xFF4D5D44),
                        onPressed: () => _recordAttendance('حضور'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildActionButton(
                        label: 'تسجيل انصراف',
                        icon: Icons.logout,
                        color: const Color(0xFF4D5D44),
                        onPressed: () => _recordAttendance('انصراف'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool readOnly = false,
    VoidCallback? onTap,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4D5D44).withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: const Color(0xFF4D5D44).withOpacity(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: const Color(0xFF4D5D44).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF4D5D44),
              size: 20,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: Color(0xFF4D5D44),
              width: 1.5,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }
  
  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF4D5D44)),
        labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
        ),
        suffixIcon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4D5D44)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: const TextStyle(color: Colors.black87),
      textAlign: TextAlign.right,
    );
  }
  
  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        shadowColor: color.withOpacity(0.4),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF4D5D44), // Army green
          elevation: 1,
          title: Text(
            selectedPage == 'fighters' ? 'المقاتلين' : 
            selectedPage == 'dashboard' ? 'لوحة التحكم' : 
            selectedPage == 'reports' ? 'التقارير' : 'تسجيل الدوام',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Row(
          children: [
            // Sidebar
            Container(
              width: 90,
              color: const Color(0xFF4D5D44), // Army green
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  _SidebarItem(
                    icon: Icons.dashboard,
                    label: 'لوحة التحكم',
                    selected: selectedPage == 'dashboard',
                    onTap: () => _onSidebarItemTap('dashboard'),
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.group,
                    label: 'المقاتلين',
                    selected: selectedPage == 'fighters',
                    onTap: () => _onSidebarItemTap('fighters'),
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.qr_code,
                    label: 'الدوام',
                    selected: selectedPage == 'attendance',
                    onTap: () => _onSidebarItemTap('attendance'),
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.bar_chart,
                    label: 'التقارير',
                    selected: selectedPage == 'reports',
                    onTap: () => _onSidebarItemTap('reports'),
                  ),
                  const SizedBox(height: 8),
                  _SidebarItem(
                    icon: Icons.settings,
                    label: 'الاعدادات',
                    selected: false,
                    onTap: () {
                      _showDatabaseInfoDialog(context);
                    },
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: selectedPage == 'fighters'
                    ? const FightersScreen()
                    : selectedPage == 'dashboard'
                        ? const DashboardScreen()
                        : selectedPage == 'reports'
                            ? const ReportsScreen()
                            : _buildDashboardContent(),
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
      color: selected ? Colors.white.withOpacity(0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
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

// Add a new ScanLineAnimation widget class
class ScanLineAnimation extends StatefulWidget {
  const ScanLineAnimation({Key? key}) : super(key: key);

  @override
  State<ScanLineAnimation> createState() => _ScanLineAnimationState();
}

class _ScanLineAnimationState extends State<ScanLineAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          painter: ScanLinePainter(progress: _animation.value),
          child: Container(),
        );
      },
    );
  }
}

// Custom painter for creating the scan line animation
class ScanLinePainter extends CustomPainter {
  final double progress;
  
  ScanLinePainter({required this.progress});
  
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    
    // Calculate scan line position
    final scanLineY = height * progress;
    
    // Draw the scan line
    final scanLinePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF4D5D44).withOpacity(0.8),
          const Color(0xFF4D5D44),
          const Color(0xFF4D5D44).withOpacity(0.8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, width, 3));
    
    // Draw the main scan line
    canvas.drawLine(
      Offset(0, scanLineY),
      Offset(width, scanLineY),
      Paint()
        ..color = const Color(0xFF4D5D44)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
    );
    
    // Draw the glowing effect on the scan line
    canvas.drawLine(
      Offset(0, scanLineY),
      Offset(width, scanLineY),
      scanLinePaint..strokeWidth = 2
    );
    
    // Draw scanner corners
    final cornerLength = width * 0.07;
    final cornerWidth = 3.0;
    final cornerPaint = Paint()
      ..color = const Color(0xFF4D5D44)
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke;
    
    // Top-left corner
    canvas.drawLine(Offset(0, cornerWidth / 2), Offset(cornerLength, cornerWidth / 2), cornerPaint);
    canvas.drawLine(Offset(cornerWidth / 2, 0), Offset(cornerWidth / 2, cornerLength), cornerPaint);
    
    // Top-right corner
    canvas.drawLine(Offset(width - cornerLength, cornerWidth / 2), Offset(width, cornerWidth / 2), cornerPaint);
    canvas.drawLine(Offset(width - cornerWidth / 2, 0), Offset(width - cornerWidth / 2, cornerLength), cornerPaint);
    
    // Bottom-left corner
    canvas.drawLine(Offset(0, height - cornerWidth / 2), Offset(cornerLength, height - cornerWidth / 2), cornerPaint);
    canvas.drawLine(Offset(cornerWidth / 2, height - cornerLength), Offset(cornerWidth / 2, height), cornerPaint);
    
    // Bottom-right corner
    canvas.drawLine(Offset(width - cornerLength, height - cornerWidth / 2), Offset(width, height - cornerWidth / 2), cornerPaint);
    canvas.drawLine(Offset(width - cornerWidth / 2, height - cornerLength), Offset(width - cornerWidth / 2, height), cornerPaint);
    
    // Draw scan area effect
    final double rippleWidth = 150.0;
    final double rippleHeight = 10.0;
    final double rippleOpacity = (1.0 - (progress * 0.7)) * 0.3;
    
    final ripplePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF4D5D44).withOpacity(rippleOpacity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(
        (width - rippleWidth) / 2, 
        scanLineY - rippleHeight / 2, 
        rippleWidth, 
        rippleHeight
      ));
    
    canvas.drawRect(
      Rect.fromLTWH(
        (width - rippleWidth) / 2, 
        scanLineY - rippleHeight / 2, 
        rippleWidth, 
        rippleHeight
      ),
      ripplePaint
    );
  }
  
  @override
  bool shouldRepaint(ScanLinePainter oldDelegate) => oldDelegate.progress != progress;
}

Widget _buildRecentAttendanceCard() {
  return Container(
    margin: const EdgeInsets.only(top: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF4D5D44).withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4D5D44).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.history,
                  color: Color(0xFF4D5D44),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'سجل الحضور الأخير',
                style: TextStyle(
                  color: Color(0xFF4D5D44),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF4D5D44), size: 20),
                onPressed: _reloadRecentAttendance,
                tooltip: 'تحديث البيانات',
              ),
            ],
          ),
        ),
        
        // Attendance list
        if (_recentAttendance.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade400, size: 48),
                const SizedBox(height: 8),
                Text(
                  'لا يوجد سجلات حضور لليوم',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _recentAttendance.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade200,
              indent: 16,
              endIndent: 16,
            ),
            itemBuilder: (context, index) {
              final record = _recentAttendance[index];
              final fighterName = record[DatabaseService.columnName] as String? ?? "غير معروف";
              final timestamp = record[DatabaseService.columnTimestamp] as String;
              final type = record[DatabaseService.columnType] as String;
              
              // Extract time from timestamp
              final timePart = timestamp.split(' ').length > 1 ? timestamp.split(' ')[1] : '';
              final formattedTime = _formatTime(
                DateFormat('yyyy-MM-dd HH:mm').parse(timestamp)
              );
              
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: type == DatabaseService.typeCheckIn
                          ? [const Color(0xFF388E3C), const Color(0xFF4CAF50)]
                          : [const Color(0xFFD32F2F), const Color(0xFFE57373)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: (type == DatabaseService.typeCheckIn 
                          ? const Color(0xFF388E3C) 
                          : const Color(0xFFD32F2F)).withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    type == DatabaseService.typeCheckIn
                        ? Icons.login
                        : Icons.logout,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  fighterName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  type == DatabaseService.typeCheckIn
                      ? 'حضور: $formattedTime'
                      : 'انصراف: $formattedTime',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getTimeAgo(timestamp),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 10,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}

String _getTimeAgo(String timestamp) {
  final recordTime = DateFormat('yyyy-MM-dd HH:mm').parse(timestamp);
  final now = DateTime.now();
  final difference = now.difference(recordTime);
  
  if (difference.inSeconds < 60) {
    return 'الآن';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes} دقيقة مضت';
  } else if (difference.inHours < 24) {
    return '${difference.inHours} ساعة مضت';
  } else {
    return '${difference.inDays} يوم مضت';
  }
}

// Build the recent attendance section for the form
Widget _buildRecentAttendanceSection() {
  return Container(
    margin: const EdgeInsets.only(top: 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF4D5D44).withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4D5D44).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.history,
                  color: Color(0xFF4D5D44),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'سجل الحضور الأخير',
                style: TextStyle(
                  color: Color(0xFF4D5D44),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFF4D5D44), size: 20),
                onPressed: _loadRecentAttendance,
                tooltip: 'تحديث البيانات',
              ),
            ],
          ),
        ),
        
        // Attendance list
        if (_recentAttendance.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade400, size: 48),
                const SizedBox(height: 8),
                Text(
                  'لا يوجد سجلات حضور لليوم',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _recentAttendance.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey.shade200,
              indent: 16,
              endIndent: 16,
            ),
            itemBuilder: (context, index) {
              final record = _recentAttendance[index];
              final fighterName = record[DatabaseService.columnName] as String? ?? "غير معروف";
              final timestamp = record[DatabaseService.columnTimestamp] as String;
              final type = record[DatabaseService.columnType] as String;
              
              // Extract time from timestamp
              final timePart = timestamp.split(' ').length > 1 ? timestamp.split(' ')[1] : '';
              final formattedTime = _formatTime(
                DateFormat('yyyy-MM-dd HH:mm').parse(timestamp)
              );
              
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: type == DatabaseService.typeCheckIn
                          ? [const Color(0xFF388E3C), const Color(0xFF4CAF50)]
                          : [const Color(0xFFD32F2F), const Color(0xFFE57373)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: (type == DatabaseService.typeCheckIn 
                          ? const Color(0xFF388E3C) 
                          : const Color(0xFFD32F2F)).withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    type == DatabaseService.typeCheckIn
                        ? Icons.login
                        : Icons.logout,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  fighterName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  type == DatabaseService.typeCheckIn
                      ? 'حضور: $formattedTime'
                      : 'انصراف: $formattedTime',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getTimeAgo(timestamp),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 10,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
} 