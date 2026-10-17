import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

const phalanxes = [
  'Exus e Pombogiras',
  'Caboclos e Caboclas',
  'Baianos e Baianas',
  'Ciganos e Ciganas',
  'Malandros e Malandras',
  'Marinheiros',
  'Preto-velhos e Preta-velhas',
];
const ribbons = {
  'yellow': 'Amarela',
  'green': 'Verde',
  'blue': 'Azul',
  'indigo': 'Índigo',
  'purple': 'Violeta',
  'colorful': 'Colorida',
  'white': 'Branca',
};

/// O dia de trabalho vira às 03h, usando o horário local do dispositivo.
String sessionDay(DateTime now) {
  final local = now.toLocal();
  final day = local.hour < 3
      ? DateTime(local.year, local.month, local.day - 1)
      : local;
  return '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

Future<void> createCatalogSchema(DatabaseExecutor db) async {
  for (final sql in [
    'CREATE TABLE nucleos (id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL)',
    'CREATE TABLE mediums (id TEXT PRIMARY KEY, name TEXT NOT NULL, degree TEXT NOT NULL, ribbon TEXT NOT NULL, active INTEGER NOT NULL, inactive_reason TEXT NOT NULL)',
    'CREATE TABLE medium_nucleos (medium_id TEXT NOT NULL REFERENCES mediums(id), nucleo_id TEXT NOT NULL REFERENCES nucleos(id), PRIMARY KEY(medium_id, nucleo_id))',
    'CREATE TABLE guides (id TEXT PRIMARY KEY, medium_id TEXT NOT NULL REFERENCES mediums(id), name TEXT NOT NULL, phalanx TEXT NOT NULL)',
    'CREATE TABLE sessions (id TEXT PRIMARY KEY, nucleo_id TEXT NOT NULL REFERENCES nucleos(id), day TEXT NOT NULL, phalanx TEXT NOT NULL, duration INTEGER NOT NULL CHECK(duration > 0), consultation_limit INTEGER NOT NULL CHECK(consultation_limit > 0), dirigent_id TEXT REFERENCES mediums(id), locked_at TEXT, UNIQUE(nucleo_id, day))',
    'CREATE TABLE attendance (session_id TEXT NOT NULL REFERENCES sessions(id), medium_id TEXT NOT NULL REFERENCES mediums(id), present INTEGER NOT NULL, PRIMARY KEY(session_id, medium_id))',
  ]) {
    await db.execute(sql);
  }
}

/// A outbox permanece local até existir confirmação de um servidor real.
Future<void> enqueueEntity(
  Transaction tx,
  String type,
  Map<String, Object?> data,
) async {
  await tx.insert('outbox', {
    'id': const Uuid().v4(),
    'consultation_id': data['id'],
    'entity_type': type,
    'entity_id': data['id'],
    'payload': jsonEncode(data),
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
}

class CatalogStore {
  CatalogStore(this.db);
  final Database db;
  Future<List<Map<String, Object?>>> nucleos() =>
      db.query('nucleos', orderBy: 'name COLLATE NOCASE');
  Future<List<Map<String, Object?>>> mediums() =>
      db.query('mediums', orderBy: 'name COLLATE NOCASE');
  Future<List<Map<String, Object?>>> guides(String mediumId) => db.query(
    'guides',
    where: 'medium_id = ?',
    whereArgs: [mediumId],
    orderBy: 'name COLLATE NOCASE',
  );
  Future<List<String>> memberships(String mediumId) async => (await db.query(
    'medium_nucleos',
    where: 'medium_id = ?',
    whereArgs: [mediumId],
  )).map((r) => r['nucleo_id'] as String).toList();
  Future<List<Map<String, Object?>>> sessions() =>
      db.query('sessions', orderBy: 'day DESC, rowid DESC');
  Future<List<Map<String, Object?>>> attendance(String sessionId) =>
      db.query('attendance', where: 'session_id = ?', whereArgs: [sessionId]);

  Future<String> saveNucleo({
    String? id,
    required String name,
    String description = '',
  }) => db.transaction((tx) async {
    if (name.trim().isEmpty) throw StateError('Informe o nome do núcleo.');
    final key = id ?? const Uuid().v4();
    final data = <String, Object?>{
      'id': key,
      'name': name.trim(),
      'description': description.trim(),
    };
    await _save(tx, 'nucleos', id, data);
    await enqueueEntity(tx, 'nucleo', data);
    return key;
  });

  Future<String> saveMedium({
    String? id,
    required String name,
    required String degree,
    required String ribbon,
    required List<String> nucleoIds,
    bool active = true,
    String inactiveReason = '',
  }) => db.transaction((tx) async {
    if (name.trim().isEmpty ||
        degree.trim().isEmpty ||
        !ribbons.containsKey(ribbon)) {
      throw StateError('Informe nome, grau e fita válidos.');
    }
    if (!active && inactiveReason.trim().isEmpty) {
      throw StateError('Informe o motivo da inativação.');
    }
    if (id != null) {
      final assigned = await tx.query(
        'consultations',
        where: 'medium_id = ? AND status != ?',
        whereArgs: [id, 'completed'],
      );
      if (assigned.isNotEmpty) {
        throw StateError(
          'Encerre as consultas e a fila deste médium antes de editar.',
        );
      }
      final directed = await tx.query(
        'sessions',
        where: 'dirigent_id = ? AND day = ?',
        whereArgs: [id, sessionDay(DateTime.now())],
      );
      if (directed.isNotEmpty && (!active || degree != 'Dirigente')) {
        throw StateError('Altere primeiro o dirigente na configuração diária.');
      }
    }
    final key = id ?? const Uuid().v4();
    final data = <String, Object?>{
      'id': key,
      'name': name.trim(),
      'degree': degree.trim(),
      'ribbon': ribbon,
      'active': active ? 1 : 0,
      'inactive_reason': active ? '' : inactiveReason.trim(),
    };
    await _save(tx, 'mediums', id, data);
    await tx.delete('medium_nucleos', where: 'medium_id = ?', whereArgs: [key]);
    for (final nucleo in nucleoIds.toSet()) {
      await tx.insert('medium_nucleos', {
        'medium_id': key,
        'nucleo_id': nucleo,
      });
    }
    await enqueueEntity(tx, 'medium', {
      ...data,
      'nucleo_ids': nucleoIds.toSet().toList(),
    });
    return key;
  });

  Future<String> saveGuide({
    String? id,
    required String mediumId,
    required String name,
    required String phalanx,
  }) => db.transaction((tx) async {
    if (name.trim().isEmpty || phalanx.trim().isEmpty) {
      throw StateError('Informe nome e falange do guia.');
    }
    final medium = await tx.query(
      'mediums',
      where: 'id = ? AND active = 1',
      whereArgs: [mediumId],
    );
    if (medium.isEmpty) throw StateError('Médium inativo ou inexistente.');
    if (id != null) {
      final old = await tx.query(
        'guides',
        where: 'id = ? AND medium_id = ?',
        whereArgs: [id, mediumId],
      );
      if (old.isEmpty) throw StateError('Guia não pertence ao médium.');
      if ((await tx.query(
        'consultations',
        where: 'guide_id = ? AND status != ?',
        whereArgs: [id, 'completed'],
      )).isNotEmpty) {
        throw StateError('Guia possui consultas pendentes.');
      }
    }
    final key = id ?? const Uuid().v4();
    final data = <String, Object?>{
      'id': key,
      'medium_id': mediumId,
      'name': name.trim(),
      'phalanx': phalanx.trim(),
    };
    await _save(tx, 'guides', id, data);
    await enqueueEntity(tx, 'guide', data);
    return key;
  });

  Future<String> saveSession({
    required String nucleoId,
    required String phalanx,
    required int duration,
    required int limit,
    String? dirigentId,
  }) => db.transaction((tx) async {
    if (phalanx.trim().isEmpty || duration <= 0 || limit <= 0) {
      throw StateError('Falange, duração e limite devem ser válidos.');
    }
    final day = sessionDay(DateTime.now());
    if (dirigentId != null) {
      final medium = await tx.query(
        'mediums',
        where: 'id = ? AND active = 1 AND degree = ?',
        whereArgs: [dirigentId, 'Dirigente'],
      );
      if (medium.isEmpty || !await belongsToNucleo(tx, dirigentId, nucleoId)) {
        throw StateError('Selecione um dirigente ativo deste núcleo.');
      }
    }
    final rows = await tx.query(
      'sessions',
      where: 'nucleo_id = ? AND day = ?',
      whereArgs: [nucleoId, day],
    );
    final old = rows.isEmpty ? null : rows.single;
    if (old != null) {
      if (old['locked_at'] != null && old['phalanx'] != phalanx.trim()) {
        throw StateError('Falange travada após o primeiro atendimento.');
      }
      final ongoing = await tx.query(
        'consultations',
        where: 'session_id = ? AND status = ?',
        whereArgs: [old['id'], 'in_progress'],
      );
      if (ongoing.isNotEmpty && old['duration'] != duration) {
        throw StateError('Encerre os atendimentos antes de alterar a duração.');
      }
      final queued = await tx.rawQuery(
        'SELECT COUNT(*) AS n FROM consultations WHERE session_id = ? AND status = ? AND guide_id IN (SELECT id FROM guides WHERE phalanx != ?)',
        [old['id'], 'queue', phalanx.trim()],
      );
      if ((queued.single['n'] as int) > 0) {
        throw StateError('A fila contém guias de outra falange.');
      }
    }
    final key = old?['id'] as String? ?? const Uuid().v4();
    final data = <String, Object?>{
      'id': key,
      'nucleo_id': nucleoId,
      'day': day,
      'phalanx': phalanx.trim(),
      'duration': duration,
      'consultation_limit': limit,
      'dirigent_id': dirigentId,
      'locked_at': old?['locked_at'],
    };
    await _save(tx, 'sessions', old?['id'] as String?, data);
    await enqueueEntity(tx, 'session', data);
    return key;
  });

  Future<void> setPresence(String sessionId, String mediumId, bool present) =>
      db.transaction((tx) async {
        final session = await currentSession(tx, sessionId);
        final medium = await tx.query(
          'mediums',
          where: 'id = ? AND active = 1',
          whereArgs: [mediumId],
        );
        if (medium.isEmpty ||
            !await belongsToNucleo(
              tx,
              mediumId,
              session['nucleo_id'] as String,
            )) {
          throw StateError('Médium não elegível neste núcleo.');
        }
        if (!present &&
            (await tx.query(
              'consultations',
              where: 'session_id = ? AND medium_id = ? AND status != ?',
              whereArgs: [sessionId, mediumId, 'completed'],
            )).isNotEmpty) {
          throw StateError('Médium possui consultas pendentes.');
        }
        final data = <String, Object?>{
          'session_id': sessionId,
          'medium_id': mediumId,
          'present': present ? 1 : 0,
        };
        await tx.insert(
          'attendance',
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await enqueueEntity(tx, 'attendance', {
          ...data,
          'id': '$sessionId/$mediumId',
        });
      });
}

Future<void> _save(
  Transaction tx,
  String table,
  String? id,
  Map<String, Object?> data,
) async {
  if (id == null) {
    await tx.insert(table, data);
  } else if (await tx.update(table, data, where: 'id = ?', whereArgs: [id]) !=
      1) {
    throw StateError('Registro não encontrado.');
  }
}

Future<bool> belongsToNucleo(
  DatabaseExecutor tx,
  String mediumId,
  String nucleoId,
) async {
  final links = await tx.query(
    'medium_nucleos',
    where: 'medium_id = ?',
    whereArgs: [mediumId],
  );
  return links.isEmpty || links.any((r) => r['nucleo_id'] == nucleoId);
}

Future<Map<String, Object?>> currentSession(
  DatabaseExecutor tx,
  String id,
) async {
  final rows = await tx.query('sessions', where: 'id = ?', whereArgs: [id]);
  if (rows.isEmpty || rows.single['day'] != sessionDay(DateTime.now())) {
    throw StateError('Configure e selecione a sessão do dia atual.');
  }
  return rows.single;
}
