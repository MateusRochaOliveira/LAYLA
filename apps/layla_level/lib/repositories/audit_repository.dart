// lib/repositories/audit_repository.dart

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Represents a forensic audit record stored locally
class AuditRecord {
  final int? id;
  final double pitch;
  final double roll;
  final bool isCompliant;
  final String gpsCoordinates;
  final String timestampUtc;
  final String? imagePath;

  const AuditRecord({
    this.id,
    required this.pitch,
    required this.roll,
    required this.isCompliant,
    required this.gpsCoordinates,
    required this.timestampUtc,
    this.imagePath,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pitch': pitch,
      'roll': roll,
      'isCompliant': isCompliant ? 1 : 0,
      'gpsCoordinates': gpsCoordinates,
      'timestampUtc': timestampUtc,
      'imagePath': imagePath,
    };
  }

  factory AuditRecord.fromMap(Map<String, dynamic> map) {
    return AuditRecord(
      id: map['id'] as int?,
      pitch: map['pitch'] as double,
      roll: map['roll'] as double,
      isCompliant: (map['isCompliant'] as int) == 1,
      gpsCoordinates: map['gpsCoordinates'] as String,
      timestampUtc: map['timestampUtc'] as String,
      imagePath: map['imagePath'] as String?,
    );
  }
}

/// SQLite Repository managing offline audit persistence
class AuditRepository {
  static Future<Database>? _databaseFuture;

  Future<Database> get database => _databaseFuture ??= _initDatabase();

  Future<Database> _initDatabase() async {
    final String dbPath = await getDatabasesPath();
    final String path = join(dbPath, 'layla_level_audits.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE audits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pitch REAL NOT NULL,
            roll REAL NOT NULL,
            isCompliant INTEGER NOT NULL,
            gpsCoordinates TEXT NOT NULL,
            timestampUtc TEXT NOT NULL,
            imagePath TEXT
          )
        ''');
      },
    );
  }

  /// Inserts a new audit record into SQLite
  Future<int> insertAudit(AuditRecord record) async {
    final db = await database;
    return await db.insert('audits', record.toMap());
  }

  /// Retrieves all recorded audits ordered by timestamp (newest first)
  Future<List<AuditRecord>> getAllAudits() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'audits',
      orderBy: 'id DESC',
    );
    return List.generate(maps.length, (i) => AuditRecord.fromMap(maps[i]));
  }

  /// Deletes an audit record by ID
  Future<int> deleteAudit(int id) async {
    final db = await database;
    return await db.delete('audits', where: 'id = ?', whereArgs: [id]);
  }
}