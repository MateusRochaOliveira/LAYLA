import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'engineering_standards.dart';

/// Inspection Data Model
class InspectionItem {
  final int? id;
  final double pitch;
  final double roll;
  final EngineeringStandard standard;
  final DateTime timestamp;

  InspectionItem({
    this.id,
    required this.pitch,
    required this.roll,
    required this.standard,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pitch': pitch,
      'roll': roll,
      'standard_id': standard.id,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory InspectionItem.fromMap(
    Map<String, dynamic> map,
    List<EngineeringStandard> availableStandards,
  ) {
    final stdId = map['standard_id'] as String?;
    final matchedStd = availableStandards.firstWhere(
      (s) => s.id == stdId,
      orElse: () => StandardsRegistry.defaultStandards.first,
    );

    return InspectionItem(
      id: map['id'] as int?,
      pitch: (map['pitch'] as num).toDouble(),
      roll: (map['roll'] as num).toDouble(),
      standard: matchedStd,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// SQLite Database Helper
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Future<Database>? _databaseFuture;

  DatabaseHelper._init();

  Future<Database> get database =>
      _databaseFuture ??= _initDB('layla_inspections.db');

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE inspections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pitch REAL NOT NULL,
        roll REAL NOT NULL,
        standard_id TEXT NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertInspection(InspectionItem item) async {
    final db = await instance.database;
    return await db.insert('inspections', item.toMap());
  }

  Future<List<InspectionItem>> getAllInspections([
    List<EngineeringStandard>? standards,
  ]) async {
    final db = await instance.database;
    final maps = await db.query('inspections', orderBy: 'id DESC');

    final availableStandards =
        standards ?? StandardsRegistry.defaultStandards;

    return maps
        .map((map) => InspectionItem.fromMap(map, availableStandards))
        .toList();
  }

  Future<int> clearAllInspections() async {
    final db = await instance.database;
    return await db.delete('inspections');
  }
}