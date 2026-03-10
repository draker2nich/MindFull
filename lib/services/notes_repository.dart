import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class NoteEntry {
  final int id;
  final String text;
  final String appPackage;
  final String appName;
  final int timestamp;

  NoteEntry({
    required this.id,
    required this.text,
    required this.appPackage,
    required this.appName,
    required this.timestamp,
  });

  factory NoteEntry.fromMap(Map<String, dynamic> map) {
    return NoteEntry(
      id: map['_id'] as int,
      text: map['text'] as String,
      appPackage: map['app_package'] as String,
      appName: map['app_name'] as String,
      timestamp: map['timestamp'] as int,
    );
  }
}

class NotesRepository {
  NotesRepository._();

  static Database? _db;

  /// Открываем ту же БД, что создаёт NoteDbHelper на Kotlin стороне.
  /// Android хранит её по умолчанию в /data/data/<pkg>/databases/
  static Future<Database> _getDb() async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'mindful_notes.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Создаём таблицу если БД ещё не существует
        // (на случай если Flutter открыл раньше чем Kotlin)
        await db.execute('''
          CREATE TABLE IF NOT EXISTS notes (
            _id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            app_package TEXT NOT NULL,
            app_name TEXT NOT NULL,
            timestamp INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<List<NoteEntry>> getAllNotes() async {
    final db = await _getDb();
    // Проверяем что таблица существует
    try {
      final rows = await db.query(
        'notes',
        orderBy: 'timestamp DESC',
      );
      return rows.map(NoteEntry.fromMap).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> deleteNote(int id) async {
    final db = await _getDb();
    await db.delete('notes', where: '_id = ?', whereArgs: [id]);
  }

  static Future<void> clearAll() async {
    final db = await _getDb();
    await db.delete('notes');
  }
}