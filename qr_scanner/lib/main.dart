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
    final process = await Process.start(
      'py',
      [scriptPath],
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
  
  // Create and initialize backend service
  final backendService = BackendService();
  
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
  };
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CameraService()),
        ChangeNotifierProvider(create: (_) => backendService),
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
      title: 'QR Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
    );
  }
}
