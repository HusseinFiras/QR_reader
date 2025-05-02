import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseService {
  static const String _databaseName = 'qr_scanner.db';
  static const int _databaseVersion = 3;
  
  // Table name
  static const String tableFighters = 'fighters';
  static const String tableDepartments = 'departments';
  
  // Column names
  static const String columnId = 'id';
  static const String columnName = 'name';
  static const String columnNumber = 'number';
  static const String columnDepartment = 'department';
  static const String columnQrCode = 'qr_code';
  static const String columnQrImagePath = 'qr_image_path';
  static const String columnStatus = 'status';
  
  // Status values
  static const String statusActive = 'فعال';
  static const String statusInactive = 'غير فعال';
  
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
  
  // Initialize the database
  Future<Database> _initDatabase() async {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // Get the application documents directory
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    
    // Open the database
    return await openDatabase(
      path,
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
  
  // Close the database
  Future<void> close() async {
    Database db = await database;
    await db.close();
  }
} 