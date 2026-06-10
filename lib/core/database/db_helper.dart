import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class Deteccion {
  final int? id;
  final String caravanaId; // Caravana individual del animal
  final String loteId;     // Lote agrupador de la jornada
  final String timestamp;
  final double pesoEstimado;
  final double condicionCorporal;
  final double llenadoRuminal;
  final String estado; // PENDIENTE / PROCESADO / FALLIDO

  Deteccion({
    this.id,
    required this.caravanaId,
    required this.loteId,
    required this.timestamp,
    required this.pesoEstimado,
    required this.condicionCorporal,
    required this.llenadoRuminal,
    required this.estado,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'caravana_id': caravanaId,
      'lote_id': loteId,
      'timestamp': timestamp,
      'peso_estimado': pesoEstimado,
      'condicion_corporal': condicionCorporal,
      'llenado_ruminal': llenadoRuminal,
      'estado': estado,
    };
  }

  factory Deteccion.fromMap(Map<String, dynamic> map) {
    return Deteccion(
      id: map['id'] as int?,
      caravanaId: map['caravana_id'] as String? ?? 'SIN-CARAVANA',
      loteId: map['lote_id'] as String,
      timestamp: map['timestamp'] as String,
      pesoEstimado: (map['peso_estimado'] as num).toDouble(),
      condicionCorporal: (map['condicion_corporal'] as num).toDouble(),
      llenadoRuminal: (map['llenado_ruminal'] as num).toDouble(),
      estado: map['estado'] as String,
    );
  }
}

class DbHelper {
  static final DbHelper instance = DbHelper._init();
  static Database? _database;

  // In-memory web fallback data structures
  final List<Deteccion> _webDetecciones = [];
  int _webIdCounter = 1;

  DbHelper._init();

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite no está soportado de forma nativa en la Web.');
    }
    if (_database != null) return _database!;
    _database = await _initDB('agrovision_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // Incremented version for schema change (added caravana_id)
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE detecciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        caravana_id TEXT NOT NULL,
        lote_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        peso_estimado REAL NOT NULL,
        condicion_corporal REAL NOT NULL,
        llenado_ruminal REAL NOT NULL,
        estado TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE detecciones ADD COLUMN caravana_id TEXT DEFAULT 'SIN-CARAVANA'");
      } catch (e) {
        debugPrint('DB_HELPER Upgrade Error: $e');
      }
    }
  }

  // CRUD Operations
  Future<int> insertDeteccion(Deteccion deteccion) async {
    if (kIsWeb) {
      final newDet = Deteccion(
        id: _webIdCounter++,
        caravanaId: deteccion.caravanaId,
        loteId: deteccion.loteId,
        timestamp: deteccion.timestamp,
        pesoEstimado: deteccion.pesoEstimado,
        condicionCorporal: deteccion.condicionCorporal,
        llenadoRuminal: deteccion.llenadoRuminal,
        estado: deteccion.estado,
      );
      _webDetecciones.add(newDet);
      return newDet.id!;
    }
    final db = await instance.database;
    return await db.insert('detecciones', deteccion.toMap());
  }

  Future<List<Deteccion>> getAllDetecciones() async {
    if (kIsWeb) {
      final list = List<Deteccion>.from(_webDetecciones);
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    }
    final db = await instance.database;
    final result = await db.query('detecciones', orderBy: 'timestamp DESC');
    return result.map((json) => Deteccion.fromMap(json)).toList();
  }

  Future<int> updateEstadoDeteccion(int id, String nuevoEstado) async {
    if (kIsWeb) {
      final index = _webDetecciones.indexWhere((element) => element.id == id);
      if (index != -1) {
        final old = _webDetecciones[index];
        _webDetecciones[index] = Deteccion(
          id: old.id,
          caravanaId: old.caravanaId,
          loteId: old.loteId,
          timestamp: old.timestamp,
          pesoEstimado: old.pesoEstimado,
          condicionCorporal: old.condicionCorporal,
          llenadoRuminal: old.llenadoRuminal,
          estado: nuevoEstado,
        );
        return 1;
      }
      return 0;
    }
    final db = await instance.database;
    return await db.update(
      'detecciones',
      {'estado': nuevoEstado},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteDeteccion(int id) async {
    if (kIsWeb) {
      final initialLength = _webDetecciones.length;
      _webDetecciones.removeWhere((element) => element.id == id);
      return initialLength - _webDetecciones.length;
    }
    final db = await instance.database;
    return await db.delete(
      'detecciones',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> clearDetecciones() async {
    if (kIsWeb) {
      final count = _webDetecciones.length;
      _webDetecciones.clear();
      return count;
    }
    final db = await instance.database;
    return await db.delete('detecciones');
  }

  Future<void> close() async {
    if (kIsWeb) return;
    final db = _database;
    if (db != null) {
      await db.close();
    }
  }
}
