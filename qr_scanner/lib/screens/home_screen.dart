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

class HomeScreen extends StatefulWidget {
  final String initialPage;
  
  const HomeScreen({Key? key, this.initialPage = 'attendance'}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late CameraService _cameraService;
  late BackendService _backendService;
  final ScannerPerformanceService _performanceService = ScannerPerformanceService();
  String? _lastQRResult;
  String? _errorMessage;
  bool _showSuccessAnimation = false;
  bool _showErrorQrAnimation = false;
  bool _isInitializing = false;

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
  
  @override
  void initState() {
    debugPrint('HomeScreen: Initializing state...');
    super.initState();
    selectedPage = widget.initialPage;
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
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
    super.dispose();
    debugPrint('HomeScreen: Disposed successfully');
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
    });
    
    Future.delayed(const Duration(milliseconds: 1500), () {
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
    });
    
    Future.delayed(const Duration(milliseconds: 1500), () {
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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0E0E0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ماسح رمز QR',
                  style: TextStyle(color: Color(0xFF4D5D44), fontSize: 20, fontWeight: FontWeight.bold),
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
                          if (_errorMessage != null && _cameraService.controller?.value.isInitialized != true)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                color: Colors.black54,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: Colors.white),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4D5D44),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _errorMessage = null;
                                        });
                                        _initializeServices();
                                      },
                                      child: const Text('إعادة المحاولة'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_showSuccessAnimation)
                            Positioned.fill(
                              child: Container(
                                color: const Color(0xFF4D5D44).withOpacity(0.3),
                                child: const Center(
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Colors.white,
                                    size: 100,
                                  ),
                                ),
                              ),
                            ),
                          if (_showErrorQrAnimation)
                            Positioned.fill(
                              child: Container(
                                color: Colors.red.withOpacity(0.3),
                                child: const Center(
                                  child: Icon(
                                    Icons.error,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE0E0E0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إدخال يدوي',
                  style: TextStyle(color: Color(0xFF4D5D44), fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 16),
                // Fighter ID field
                TextField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: 'رقم المقاتل (ID)',
                    labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
                    ),
                  ),
                  readOnly: true, // ID is read-only, set by QR scan
                  style: const TextStyle(color: Colors.black87),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 16),
                // Fighter name field
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'اسم المقاتل',
                    labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
                    ),
                  ),
                  readOnly: true, // Name is read-only, set by QR scan
                  style: const TextStyle(color: Colors.black87),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 16),
                // Fighter phone number field
                TextField(
                  controller: _numberController,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
                    ),
                  ),
                  style: const TextStyle(color: Colors.black87),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 16),
                // Fighter department field
                TextField(
                  controller: _departmentController,
                  decoration: InputDecoration(
                    labelText: 'القسم',
                    labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
                    ),
                  ),
                  readOnly: true, // Department is read-only, set by QR scan
                  style: const TextStyle(color: Colors.black87),
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
                          labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
                          ),
                        ),
                        style: const TextStyle(color: Colors.black87),
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
                          labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
                          ),
                        ),
                        style: const TextStyle(color: Colors.black87),
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
                    labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF4D5D44), width: 2),
                    ),
                  ),
                  style: const TextStyle(color: Colors.black87),
                  textAlign: TextAlign.right,
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4D5D44),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.login),
                        label: const Text('تسجيل حضور يدوي'),
                        onPressed: () {
                          _recordAttendance('حضور');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4D5D44),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text('تسجيل انصراف يدوي'),
                        onPressed: () {
                          _recordAttendance('انصراف');
                        },
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