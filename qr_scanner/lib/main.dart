import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:camera_windows/camera_windows.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'screens/home_screen.dart';
import 'services/camera_service.dart';
import 'services/app_lifecycle_service.dart';
import 'services/backend_service.dart';
import 'services/database_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void initializeWindowsCamera() {
  if (defaultTargetPlatform == TargetPlatform.windows) {
    CameraPlatform.instance = CameraWindows();
  }
}

Future<Process?> startPythonBackend() async {
  try {
    final String scriptPath = path.join(Directory.current.path, 'python_backend', 'qr_server.py');
    final String readyFilePath = path.join(Directory.current.path, 'python_backend', 'server_ready');
    final String logFilePath = path.join(Directory.current.path, 'python_backend', 'qr_server.log');
    
    debugPrint('Starting Python backend server...');
    debugPrint('Script path: $scriptPath');
    debugPrint('Ready file path: $readyFilePath');
    debugPrint('Log file path: $logFilePath');
    
    // Remove ready file if it exists from previous run
    if (File(readyFilePath).existsSync()) {
      await File(readyFilePath).delete();
      debugPrint('Removed existing ready file');
    }
    
    // Remove log file if it exists
    if (File(logFilePath).existsSync()) {
      await File(logFilePath).delete();
      debugPrint('Removed existing log file');
    }
    
    if (!File(scriptPath).existsSync()) {
      debugPrint('Python backend script not found at: $scriptPath');
      return null;
    }

    debugPrint('Starting Python backend server...');
    final String vbsPath = path.join(Directory.current.path, 'python_backend', 'start_qr_server.vbs');
    
    if (!File(vbsPath).existsSync()) {
      debugPrint('VBS wrapper script not found at: $vbsPath');
      return null;
    }
    
    debugPrint('Using VBS wrapper to start Python server invisibly...');
    final process = await Process.start(
      'wscript.exe',
      [vbsPath, scriptPath],
      mode: ProcessStartMode.detached,
      runInShell: true
    );
    
    debugPrint('Started Python backend server with PID: ${process.pid}');
    
    // Listen to process output for debugging
    process.stdout.transform(const SystemEncoding().decoder).listen((data) {
      debugPrint('Python backend stdout: $data');
    });
    
    process.stderr.transform(const SystemEncoding().decoder).listen((data) {
      debugPrint('Python backend stderr: $data');
    });

    // Wait for the server to be ready by checking for the ready file
    bool serverReady = false;
    int attempts = 0;
    const maxAttempts = 30; // Wait up to 30 seconds
    
    while (!serverReady && attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));
      
      // Check if the server crashed by looking at the log file
      if (File(logFilePath).existsSync()) {
        final logContent = await File(logFilePath).readAsString();
        debugPrint('Log file content: $logContent');
        
        if (logContent.contains('Server crashed') || 
            logContent.contains('Failed to start server') ||
            logContent.contains('Error:')) {
          debugPrint('Python backend server crashed. Log content:');
          debugPrint(logContent);
          process.kill();
          return null;
        }
      }
      
      if (File(readyFilePath).existsSync()) {
        final readyContent = await File(readyFilePath).readAsString();
        debugPrint('Server ready file content: $readyContent');
        serverReady = true;
        debugPrint('Python backend server is ready');
        break;
      }
      attempts++;
      debugPrint('Waiting for Python backend server... (attempt $attempts/$maxAttempts)');
    }
    
    if (!serverReady) {
      debugPrint('Timeout waiting for Python backend server to start');
      if (File(logFilePath).existsSync()) {
        final logContent = await File(logFilePath).readAsString();
        debugPrint('Final log file content: $logContent');
      }
      process.kill();
      return null;
    }

    return process;
  } catch (e, stackTrace) {
    debugPrint('Failed to start Python backend: $e');
    debugPrint('Stack trace: $stackTrace');
    return null;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize window management
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  // Initialize camera platform
  initializeWindowsCamera();
  
  // Initialize app lifecycle service
  final appLifecycleService = AppLifecycleService();
  appLifecycleService.initialize();
  
  // Set up database directory - store in an easily accessible location
  final appDir = Directory.current.path;
  final dbDir = path.join(appDir, 'database');
  
  // Create the database directory if it doesn't exist
  final dbDirObj = Directory(dbDir);
  if (!dbDirObj.existsSync()) {
    dbDirObj.createSync(recursive: true);
  }
  
  debugPrint('Setting database directory to: $dbDir');
  DatabaseService.setCustomDatabaseDirectory(dbDir);
  
  // Create and initialize backend service
  final backendService = BackendService();
  
  // Initialize database service
  final databaseService = DatabaseService.instance;
  await databaseService.database; // This will create the database if it doesn't exist
  
  // Start Python backend server
  final pythonProcess = await startPythonBackend();
  if (pythonProcess == null) {
    debugPrint('Warning: Failed to start Python backend');
  } else {
    // Connect to the backend server
    try {
      await backendService.connect();
    } catch (e) {
      debugPrint('Warning: Failed to connect to Python backend: $e');
    }
  }
  
  // Set up process cleanup on app exit
  appLifecycleService.onExit = () async {
    if (pythonProcess != null) {
      debugPrint('Terminating Python backend process...');
      await backendService.disconnect();
      pythonProcess.kill();
    }
    // Close the database connection
    await databaseService.close();
  };
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CameraService()),
        ChangeNotifierProvider(create: (_) => backendService),
        Provider<DatabaseService>(create: (_) => databaseService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'QR Scanner',
      theme: ThemeData(
        primaryColor: const Color(0xFF4D5D44), // Army green
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF4D5D44),
          secondary: const Color(0xFF90A783), // Lighter army green
          background: Colors.white,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onBackground: Colors.black87,
          onSurface: Colors.black87,
          primaryContainer: const Color(0xFFE8EDE5), // Super light army green for containers
        ),
        useMaterial3: true,
        fontFamily: 'NotoSansArabic',
        scaffoldBackgroundColor: Colors.white,
        cardTheme: CardTheme(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          shadowColor: Colors.black.withOpacity(0.1),
          clipBehavior: Clip.antiAlias,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF4D5D44),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'NotoSansArabic',
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4D5D44),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 4,
            shadowColor: const Color(0xFF4D5D44).withOpacity(0.4),
            textStyle: const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF4D5D44),
            textStyle: const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[50],
          labelStyle: const TextStyle(
            color: Color(0xFF4D5D44),
            fontFamily: 'NotoSansArabic',
          ),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          alignLabelWithHint: true,
          floatingLabelAlignment: FloatingLabelAlignment.start,
          isCollapsed: false,
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF4D5D44),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade200,
          thickness: 1,
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (states.contains(MaterialState.selected)) {
              return const Color(0xFF4D5D44);
            }
            return Colors.grey.shade400;
          }),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        radioTheme: RadioThemeData(
          fillColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (states.contains(MaterialState.selected)) {
              return const Color(0xFF4D5D44);
            }
            return Colors.grey.shade400;
          }),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFE8EDE5),
          labelStyle: const TextStyle(color: Color(0xFF4D5D44)),
          selectedColor: const Color(0xFF4D5D44),
          secondarySelectedColor: const Color(0xFF4D5D44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          secondaryLabelStyle: const TextStyle(color: Colors.white),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
          displayMedium: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
          displaySmall: TextStyle(
            fontFamily: 'NotoSansArabic', 
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87, 
            fontWeight: FontWeight.bold,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
          headlineSmall: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
          titleLarge: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
          titleMedium: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
          titleSmall: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
          ),
          bodySmall: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black54,
          ),
          labelLarge: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
          labelMedium: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black87,
          ),
          labelSmall: TextStyle(
            fontFamily: 'NotoSansArabic',
            color: Colors.black54,
          ),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      locale: const Locale('ar'),
      home: const HomeScreen(initialPage: 'attendance'),
    );
  }
}
