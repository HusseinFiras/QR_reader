import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static const String _databaseName = 'qr_scanner.db';
  static const int _databaseVersion = 4;
  
  // Custom database directory
  static String? _customDatabaseDir;
  
  // Table names
  static const String tableFighters = 'fighters';
  static const String tableDepartments = 'departments';
  static const String tableAttendance = 'attendance';
  
  // Column names
  static const String columnId = 'id';
  static const String columnName = 'name';
  static const String columnNumber = 'number';
  static const String columnDepartment = 'department';
  static const String columnQrCode = 'qr_code';
  static const String columnQrImagePath = 'qr_image_path';
  static const String columnStatus = 'status';
  
  // Attendance columns
  static const String columnFighterId = 'fighter_id';
  static const String columnTimestamp = 'timestamp';
  static const String columnType = 'type';
  static const String columnNotes = 'notes';
  
  // Status & Type values
  static const String statusActive = 'فعال';
  static const String statusInactive = 'غير فعال';
  static const String typeCheckIn = 'حضور';
  static const String typeCheckOut = 'انصراف';
  
  // Make this a singleton class
  DatabaseService._privateConstructor();
  static final DatabaseService instance = DatabaseService._privateConstructor();
  
  // Only have a single app-wide reference to the database
  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  // Set a custom database directory
  static void setCustomDatabaseDirectory(String path) {
    _customDatabaseDir = path;
    debugPrint('DatabaseService: Custom database directory set to: $path');
  }
  
  // Get the current database path
  static Future<String> getDatabasePath() async {
    if (_customDatabaseDir != null) {
      return join(_customDatabaseDir!, _databaseName);
    } else {
      // Default to application documents directory
      Directory appDir = await getApplicationDocumentsDirectory();
      return join(appDir.path, _databaseName);
    }
  }
  
  // Initialize the database
  Future<Database> _initDatabase() async {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // Create a fixed location for the database
    String dbPath;
    
    if (_customDatabaseDir != null) {
      // Use custom directory if set
      dbPath = join(_customDatabaseDir!, _databaseName);
      
      // Make sure the directory exists
      Directory dir = Directory(_customDatabaseDir!);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } else {
      // Default path: use app's root directory or workspace directory
      String defaultDir = Directory.current.path;
      
      // Create a data directory in the app folder
      String dataDir = join(defaultDir, 'data');
      Directory dir = Directory(dataDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      
      dbPath = join(dataDir, _databaseName);
    }
    
    debugPrint('DatabaseService: Database path: $dbPath');
    
    // Open the database
    return await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }
  
  // Create the database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableFighters (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL,
        $columnNumber TEXT NOT NULL UNIQUE,
        $columnDepartment TEXT NOT NULL,
        $columnQrCode TEXT NOT NULL UNIQUE,
        $columnQrImagePath TEXT NOT NULL,
        $columnStatus TEXT NOT NULL DEFAULT '${statusActive}'
      )
    ''');
    await db.execute('''
      CREATE TABLE $tableDepartments (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE $tableAttendance (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnFighterId INTEGER NOT NULL,
        $columnTimestamp TEXT NOT NULL,
        $columnType TEXT NOT NULL,
        $columnNotes TEXT,
        FOREIGN KEY ($columnFighterId) REFERENCES $tableFighters ($columnId)
      )
    ''');
  }
  
  // Upgrade the database
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE $tableFighters
        ADD COLUMN $columnStatus TEXT NOT NULL DEFAULT '${statusActive}'
      ''');
    }
    if (oldVersion < 3) {
      // Rename job_title to department and add departments table
      await db.execute('''
        ALTER TABLE $tableFighters RENAME TO fighters_old;
      ''');
      await db.execute('''
        CREATE TABLE $tableFighters (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnName TEXT NOT NULL,
          $columnNumber TEXT NOT NULL UNIQUE,
          $columnDepartment TEXT NOT NULL,
          $columnQrCode TEXT NOT NULL UNIQUE,
          $columnQrImagePath TEXT NOT NULL,
          $columnStatus TEXT NOT NULL DEFAULT '${statusActive}'
        )
      ''');
      await db.execute('''
        INSERT INTO $tableFighters ($columnId, $columnName, $columnNumber, $columnDepartment, $columnQrCode, $columnQrImagePath, $columnStatus)
        SELECT $columnId, $columnName, $columnNumber, job_title, $columnQrCode, $columnQrImagePath, $columnStatus FROM fighters_old;
      ''');
      await db.execute('DROP TABLE fighters_old;');
      await db.execute('''
        CREATE TABLE $tableDepartments (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnName TEXT NOT NULL UNIQUE
        )
      ''');
    }
    if (oldVersion < 4) {
      // Add attendance table in version 4
      await db.execute('''
        CREATE TABLE $tableAttendance (
          $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
          $columnFighterId INTEGER NOT NULL,
          $columnTimestamp TEXT NOT NULL,
          $columnType TEXT NOT NULL,
          $columnNotes TEXT,
          FOREIGN KEY ($columnFighterId) REFERENCES $tableFighters ($columnId)
        )
      ''');
    }
  }
  
  // Insert a fighter into the database
  Future<int> insertFighter(Map<String, dynamic> fighter) async {
    Database db = await database;
    return await db.insert(tableFighters, fighter);
  }
  
  // Get all fighters
  Future<List<Map<String, dynamic>>> getAllFighters() async {
    Database db = await database;
    return await db.query(tableFighters);
  }
  
  // Get active fighters only
  Future<List<Map<String, dynamic>>> getActiveFighters() async {
    Database db = await database;
    return await db.query(
      tableFighters,
      where: '$columnStatus = ?',
      whereArgs: [statusActive],
    );
  }
  
  // Get a fighter by ID
  Future<Map<String, dynamic>?> getFighter(int id) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      tableFighters,
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  // Get a fighter by QR code
  Future<Map<String, dynamic>?> getFighterByQrCode(String qrCode) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      tableFighters,
      where: '$columnQrCode = ?',
      whereArgs: [qrCode],
    );
    return results.isNotEmpty ? results.first : null;
  }
  
  // Update a fighter
  Future<int> updateFighter(Map<String, dynamic> fighter) async {
    Database db = await database;
    return await db.update(
      tableFighters,
      fighter,
      where: '$columnId = ?',
      whereArgs: [fighter[columnId]],
    );
  }
  
  // Update fighter status
  Future<int> updateFighterStatus(int id, String status) async {
    Database db = await database;
    return await db.update(
      tableFighters,
      {columnStatus: status},
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }
  
  // Delete a fighter
  Future<int> deleteFighter(int id) async {
    Database db = await database;
    return await db.delete(
      tableFighters,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }
  
  // Department management
  Future<int> insertDepartment(String name) async {
    Database db = await database;
    return await db.insert(tableDepartments, {columnName: name}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  Future<List<String>> getAllDepartments() async {
    Database db = await database;
    final result = await db.query(tableDepartments);
    return result.map((row) => row[columnName] as String).toList();
  }
  
  // Attendance management
  Future<int> recordAttendance(Map<String, dynamic> attendance) async {
    Database db = await database;
    return await db.insert(tableAttendance, attendance);
  }
  
  Future<List<Map<String, dynamic>>> getAttendanceRecords(int fighterId) async {
    Database db = await database;
    return await db.query(
      tableAttendance,
      where: '$columnFighterId = ?',
      whereArgs: [fighterId],
      orderBy: '$columnTimestamp DESC',
    );
  }
  
  Future<List<Map<String, dynamic>>> getAllAttendanceRecords() async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT a.*, f.$columnName, f.$columnNumber, f.$columnDepartment
      FROM $tableAttendance a
      JOIN $tableFighters f ON a.$columnFighterId = f.$columnId
      ORDER BY a.$columnTimestamp DESC
    ''');
  }
  
  // Get attendance records for a specific date
  Future<List<Map<String, dynamic>>> getAttendanceByDate(String date) async {
    Database db = await database;
    
    // Search for timestamp starting with the date
    String likePattern = '$date%';
    
    // Join with fighters table to get fighter details
    return await db.rawQuery('''
      SELECT a.*, f.name, f.number, f.department
      FROM $tableAttendance a
      JOIN $tableFighters f ON a.$columnFighterId = f.$columnId
      WHERE a.$columnTimestamp LIKE ?
      ORDER BY a.$columnTimestamp DESC
    ''', [likePattern]);
  }
  
  // Get attendance records between two dates
  Future<List<Map<String, dynamic>>> getAttendanceBetweenDates(String startDate, String endDate) async {
    Database db = await database;
    
    // Join with fighters table to get fighter details
    return await db.rawQuery('''
      SELECT a.*, f.name, f.number, f.department
      FROM $tableAttendance a
      JOIN $tableFighters f ON a.$columnFighterId = f.$columnId
      WHERE a.$columnTimestamp >= ? AND a.$columnTimestamp < ?
      ORDER BY a.$columnTimestamp DESC
    ''', [startDate, endDate]);
  }
  
  // Close the database
  Future<void> close() async {
    Database db = await database;
    await db.close();
  }
} 