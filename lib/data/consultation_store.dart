import 'catalog_store.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Todas as alterações de negócio e sua operação pendente são atômicas.
class ConsultationStore {
  ConsultationStore(this.db);
  final Database db;
  static Future<ConsultationStore> open(
    DatabaseFactory factory,
    String path,
  ) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await createCatalogSchema(db);
            await db.execute(
              'ALTER TABLE consultations RENAME TO consultations_v1',
            );
            await _createConsultations(db);
            await db.execute(
              'INSERT INTO consultations (id,password,consultant,medium,status,started_at,ended_at,rating,feedback) SELECT id,password,consultant,medium,status,started_at,ended_at,rating,feedback FROM consultations_v1',
            );
            await db.execute('DROP TABLE consultations_v1');
            await db.execute(
              "ALTER TABLE outbox ADD COLUMN entity_type TEXT NOT NULL DEFAULT 'consultation'",
            );
            await db.execute('ALTER TABLE outbox ADD COLUMN entity_id TEXT');
            await db.execute('UPDATE outbox SET entity_id = consultation_id');
          }
        },
        onCreate: (db, _) async {
          await createCatalogSchema(db);
          await _createConsultations(db);
          await db.execute(
            'CREATE TABLE outbox (id TEXT PRIMARY KEY, consultation_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL)',
          );
        },
      ),
    );
    return ConsultationStore(db);
  }

  Future<List<Map<String, Object?>>> all() =>
      db.query('consultations', orderBy: 'rowid DESC');
  Future<int> pendingCount() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM outbox')).first['n'] as int;
  Future<void> _enqueue(Transaction tx, String id) async {
    final record = (await tx.query(
      'consultations',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    await enqueueEntity(tx, 'consultation', record);
  }

  CatalogStore get catalog => CatalogStore(db);

  Future<void> create(
    String password,
    String consultant,
    String mediumId, {
    required String sessionId,
    required String guideId,
  }) async {
    if ([password, consultant].any((s) => s.trim().isEmpty)) {
      throw StateError('Preencha senha e consulente.');
    }
    if (!RegExp(r'^[0-9]{1,4}$').hasMatch(password.trim())) {
      throw StateError('A senha deve conter de 1 a 4 dígitos.');
    }
    await db.transaction((tx) async {
      final session = await currentSession(tx, sessionId);
      final medium = await _eligible(tx, session, mediumId, guideId);
      final counts = await tx.rawQuery(
        'SELECT COUNT(*) AS n FROM consultations WHERE session_id = ? AND medium_id = ?',
        [sessionId, mediumId],
      );
      if ((counts.single['n'] as int) >=
          (session['consultation_limit'] as int)) {
        throw StateError('Limite diário deste médium atingido.');
      }
      final duplicate = await tx.query(
        'consultations',
        where: 'session_id = ? AND password = ?',
        whereArgs: [sessionId, password.trim()],
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Senha já utilizada neste núcleo e dia.');
      }
      final guide = (await tx.query(
        'guides',
        where: 'id = ?',
        whereArgs: [guideId],
      )).single;
      final id = const Uuid().v4();
      await tx.insert('consultations', {
        'id': id,
        'password': password.trim(),
        'consultant': consultant.trim(),
        'medium': medium['name'],
        'medium_id': mediumId,
        'guide_id': guideId,
        'guide_name': guide['name'],
        'session_id': sessionId,
        'nucleo_id': session['nucleo_id'],
        'duration': session['duration'],
        'status': 'queue',
      });
      await _enqueue(tx, id);
    });
  }

  Future<Map<String, Object?>> _eligible(
    Transaction tx,
    Map<String, Object?> session,
    String mediumId,
    String guideId,
  ) async {
    final rows = await tx.query(
      'mediums',
      where: 'id = ? AND active = 1',
      whereArgs: [mediumId],
    );
    if (rows.isEmpty ||
        !await belongsToNucleo(tx, mediumId, session['nucleo_id'] as String)) {
      throw StateError('Médium não elegível neste núcleo.');
    }
    final present = await tx.query(
      'attendance',
      where: 'session_id = ? AND medium_id = ? AND present = 1',
      whereArgs: [session['id'], mediumId],
    );
    if (present.isEmpty) {
      throw StateError('Marque a presença do médium nesta sessão.');
    }
    final guides = await tx.query(
      'guides',
      where: 'id = ? AND medium_id = ? AND phalanx = ?',
      whereArgs: [guideId, mediumId, session['phalanx']],
    );
    if (guides.isEmpty) {
      throw StateError('Selecione um guia deste médium e da falange do dia.');
    }
    return rows.single;
  }

  Future<void> start(String id) async {
    await db.transaction((tx) async {
      final rows = await tx.query(
        'consultations',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty || rows.single['status'] != 'queue') {
        throw StateError('Consulta não está na fila.');
      }
      final row = rows.single;
      int? duration;
      if (row['session_id'] != null) {
        final session = await currentSession(tx, row['session_id'] as String);
        await _eligible(
          tx,
          session,
          row['medium_id'] as String,
          row['guide_id'] as String,
        );
        duration = session['duration'] as int;
        if (session['locked_at'] == null) {
          final locked = DateTime.now().toUtc().toIso8601String();
          await tx.update(
            'sessions',
            {'locked_at': locked},
            where: 'id = ?',
            whereArgs: [session['id']],
          );
          await enqueueEntity(tx, 'session', {...session, 'locked_at': locked});
        }
      }
      final busy = await tx.query(
        'consultations',
        where: row['medium_id'] == null ? 'medium = ? AND status = ?' : '(medium_id = ? OR (medium_id IS NULL AND medium = ?)) AND status = ?',
        whereArgs: row['medium_id'] == null
            ? [row['medium'], 'in_progress']
            : [row['medium_id'], row['medium'], 'in_progress'],
      );
      if (busy.isNotEmpty) {
        throw StateError('Este médium já está em atendimento.');
      }
      await tx.update(
        'consultations',
        {
          'status': 'in_progress',
          'duration': ?duration,
          'started_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _enqueue(tx, id);
    });
  }

  Future<void> finish(String id, int rating, String feedback) async {
    if (rating < 1 || rating > 5) {
      throw StateError('Escolha uma avaliação de 1 a 5.');
    }
    await db.transaction((tx) async {
      final rows = await tx.query(
        'consultations',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Consulta não encontrada.');
      if (rows.single['status'] == 'completed') {
        return; // Reenvio não duplica encerramento.
      }
      if (rows.single['status'] != 'in_progress') {
        throw StateError('Inicie a consulta antes de encerrar.');
      }
      await tx.update(
        'consultations',
        {
          'status': 'completed',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'rating': rating,
          'feedback': feedback.trim(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _enqueue(tx, id);
    });
  }
}

Future<void> _createConsultations(DatabaseExecutor db) async {
  await db.execute(
    'CREATE TABLE consultations (id TEXT PRIMARY KEY, password TEXT NOT NULL, consultant TEXT NOT NULL, medium TEXT NOT NULL, status TEXT NOT NULL, started_at TEXT, ended_at TEXT, rating INTEGER, feedback TEXT, session_id TEXT REFERENCES sessions(id), nucleo_id TEXT REFERENCES nucleos(id), medium_id TEXT REFERENCES mediums(id), guide_id TEXT REFERENCES guides(id), guide_name TEXT, duration INTEGER)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX consultation_password_session ON consultations(session_id, password) WHERE session_id IS NOT NULL',
  );
  await db.execute(
    'CREATE UNIQUE INDEX consultation_password_legacy ON consultations(password) WHERE session_id IS NULL',
  );
}
