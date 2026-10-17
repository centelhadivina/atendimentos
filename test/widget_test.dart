import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:centelha_consultas/data/catalog_store.dart';
import 'package:centelha_consultas/data/consultation_store.dart';
import 'package:centelha_consultas/legacy/local_app.dart';

Future<({String nucleo, String medium, String guide, String session})> setup(
  ConsultationStore store, {
  String? nucleo,
  String? medium,
  int limit = 10,
}) async {
  final c = store.catalog;
  final n = nucleo ?? await c.saveNucleo(name: 'Núcleo teste');
  final m =
      medium ??
      await c.saveMedium(
        name: 'Médium teste',
        degree: 'Dirigente',
        ribbon: 'green',
        nucleoIds: [n],
      );
  final g = await c.saveGuide(
    mediumId: m,
    name: 'Guia teste',
    phalanx: phalanxes.first,
  );
  final s = await c.saveSession(
    nucleoId: n,
    phalanx: phalanxes.first,
    duration: 15,
    limit: limit,
    dirigentId: m,
  );
  await c.setPresence(s, m, true);
  return (nucleo: n, medium: m, guide: g, session: s);
}

void main() {
  test(
    'Persistência, bloqueio da falange, feedback e outbox atômica',
    () async {
      final dir = await Directory.systemTemp.createTemp('centelha_test');
      final path = '${dir.path}/test.db';
      var store = await ConsultationStore.open(databaseFactoryFfi, path);
      try {
        final f = await setup(store);
        await store.create(
          '001',
          'Pessoa',
          f.medium,
          sessionId: f.session,
          guideId: f.guide,
        );
        final id = (await store.all()).single['id'] as String;
        await expectLater(store.finish(id, 5, ''), throwsStateError);
        await store.start(id);
        final pending = await store.pendingCount();
        await store.db.close();
        store = await ConsultationStore.open(databaseFactoryFfi, path);
        expect((await store.all()).single['status'], 'in_progress');
        expect((await store.catalog.guides(f.medium)).single['id'], f.guide);
        expect(await store.catalog.memberships(f.medium), [f.nucleo]);
        await expectLater(
          store.catalog.saveSession(
            nucleoId: f.nucleo,
            phalanx: phalanxes[1],
            duration: 15,
            limit: 10,
          ),
          throwsStateError,
        );
        await expectLater(
          store.catalog.saveSession(
            nucleoId: f.nucleo,
            phalanx: phalanxes.first,
            duration: 20,
            limit: 10,
          ),
          throwsStateError,
        );
        expect(await store.pendingCount(), pending);
        await expectLater(store.finish(id, 0, ''), throwsStateError);
        await store.finish(id, 5, 'Bom atendimento');
        await store.finish(id, 5, 'Reenvio');
        expect(await store.pendingCount(), pending + 1);
        expect((await store.all()).single['feedback'], 'Bom atendimento');
        final types = (await store.db.query('outbox'))
            .map((r) => r['entity_type'])
            .toSet();
        expect(
          types,
          containsAll([
            'nucleo',
            'medium',
            'guide',
            'session',
            'attendance',
            'consultation',
          ]),
        );
      } finally {
        await store.db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'IDs, presença, falange, limite, senha por sessão e exclusividade global',
    () async {
      final store = await ConsultationStore.open(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      try {
        final f = await setup(store, limit: 2);
        final c = store.catalog;
        final n2 = await c.saveNucleo(name: 'Outro núcleo');
        final s2 = await c.saveSession(
          nucleoId: n2,
          phalanx: phalanxes.first,
          duration: 10,
          limit: 10,
        );
        final before = await store.pendingCount();
        await expectLater(c.setPresence(s2, f.medium, true), throwsStateError);
        await expectLater(
          store.create(
            'x',
            'Pessoa',
            f.medium,
            sessionId: s2,
            guideId: f.guide,
          ),
          throwsStateError,
        );
        await c.setPresence(f.session, f.medium, false);
        await expectLater(
          store.create(
            'x',
            'Pessoa',
            f.medium,
            sessionId: f.session,
            guideId: f.guide,
          ),
          throwsStateError,
        );
        await c.setPresence(f.session, f.medium, true);
        final wrong = await c.saveGuide(
          mediumId: f.medium,
          name: 'Outro guia',
          phalanx: phalanxes[1],
        );
        await expectLater(
          store.create(
            'x',
            'Pessoa',
            f.medium,
            sessionId: f.session,
            guideId: wrong,
          ),
          throwsStateError,
        );
        await store.create(
          '001',
          'Pessoa A',
          f.medium,
          sessionId: f.session,
          guideId: f.guide,
        );
        await expectLater(
          store.create(
            '001',
            'Pessoa B',
            f.medium,
            sessionId: f.session,
            guideId: f.guide,
          ),
          throwsStateError,
        );
        await store.create(
          '002',
          'Pessoa B',
          f.medium,
          sessionId: f.session,
          guideId: f.guide,
        );
        await expectLater(
          store.create(
            '003',
            'Pessoa C',
            f.medium,
            sessionId: f.session,
            guideId: f.guide,
          ),
          throwsStateError,
        );
        final rows = await store.all();
        await store.start(rows.first['id'] as String);
        final count = await store.pendingCount();
        await expectLater(
          store.start(rows.last['id'] as String),
          throwsStateError,
        );
        expect(await store.pendingCount(), count);
        await expectLater(
          c.setPresence(f.session, f.medium, false),
          throwsStateError,
        );
        await expectLater(
          c.saveMedium(
            id: f.medium,
            name: 'Mudou',
            degree: 'Verde',
            ribbon: 'green',
            nucleoIds: [],
          ),
          throwsStateError,
        );
        await expectLater(
          c.saveGuide(
            id: f.guide,
            mediumId: f.medium,
            name: 'Mudou',
            phalanx: phalanxes[1],
          ),
          throwsStateError,
        );
        expect(
          (await c.guides(f.medium))
              .firstWhere((g) => g['id'] == f.guide)['name'],
          'Guia teste',
        );
        expect(count, greaterThan(before));
        // Outro médium e núcleo podem usar a mesma senha.
        final f2 = await setup(store, nucleo: n2);
        await store.create(
          '001',
          'Pessoa C',
          f2.medium,
          sessionId: f2.session,
          guideId: f2.guide,
        );
        expect((await store.all()).length, 3);
      } finally {
        await store.db.close();
      }
    },
  );

  test(
    'Cadastro edita IDs, inativa com motivo e reativa sem apagar histórico',
    () async {
      final store = await ConsultationStore.open(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      try {
        final c = store.catalog;
        final n = await c.saveNucleo(name: 'N');
        final m = await c.saveMedium(
          name: 'M',
          degree: 'Verde',
          ribbon: 'green',
          nucleoIds: [n],
        );
        final g = await c.saveGuide(
          mediumId: m,
          name: 'G',
          phalanx: phalanxes.first,
        );
        await c.saveNucleo(id: n, name: 'N editado', description: 'Descrição');
        await c.saveGuide(
          id: g,
          mediumId: m,
          name: 'Guia editado',
          phalanx: phalanxes.first,
        );
        await expectLater(
          c.saveMedium(
            id: m,
            name: 'M',
            degree: 'Verde',
            ribbon: 'green',
            nucleoIds: [n],
            active: false,
          ),
          throwsStateError,
        );
        await c.saveMedium(
          id: m,
          name: 'M',
          degree: 'Verde',
          ribbon: 'green',
          nucleoIds: [n],
          active: false,
          inactiveReason: 'Afastamento',
        );
        final s = await c.saveSession(
          nucleoId: n,
          phalanx: phalanxes.first,
          duration: 15,
          limit: 10,
        );
        await expectLater(c.setPresence(s, m, true), throwsStateError);
        await expectLater(
          c.saveSession(
            nucleoId: n,
            phalanx: phalanxes.first,
            duration: 15,
            limit: 10,
            dirigentId: m,
          ),
          throwsStateError,
        );
        await c.saveMedium(
          id: m,
          name: 'M editado',
          degree: 'Verde',
          ribbon: 'green',
          nucleoIds: [n],
        );
        expect((await c.mediums()).single['id'], m);
        expect((await c.guides(m)).single['id'], g);
        final count = await store.pendingCount();
        await expectLater(
          c.saveMedium(
            name: 'Inválido',
            degree: 'Verde',
            ribbon: 'green',
            nucleoIds: ['inexistente'],
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect((await c.mediums()).length, 1);
        expect(await store.pendingCount(), count);
      } finally {
        await store.db.close();
      }
    },
  );

  test('Migração v1 preserva consultas, feedback e operações sem inventar vínculos', () async {
    final dir = await Directory.systemTemp.createTemp('centelha_migration');
    final path = '${dir.path}/v1.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE consultations (id TEXT PRIMARY KEY, password TEXT NOT NULL UNIQUE, consultant TEXT NOT NULL, medium TEXT NOT NULL, status TEXT NOT NULL, started_at TEXT, ended_at TEXT, rating INTEGER, feedback TEXT)',
          );
          await db.execute(
            'CREATE TABLE outbox (id TEXT PRIMARY KEY, consultation_id TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)',
          );
          await db.insert('consultations', {
            'id': 'old',
            'password': '001',
            'consultant': 'Antigo',
            'medium': 'M antigo',
            'status': 'in_progress',
            'started_at': DateTime.now().toUtc().toIso8601String(),
          });
          await db.insert('outbox', {
            'id': 'op',
            'consultation_id': 'old',
            'payload': '{"id":"old"}',
            'created_at': '2026-01-01',
          });
        },
      ),
    );
    await db.close();
    final store = await ConsultationStore.open(databaseFactoryFfi, path);
    try {
      final old = (await store.all()).single;
      expect(old['session_id'], isNull);
      expect(old['medium'], 'M antigo');
      expect(
        (await store.db.query('outbox')).single['payload'],
        '{"id":"old"}',
      );
      await store.finish('old', 4, 'Contingência');
      expect(await store.pendingCount(), 2);
      final f = await setup(store);
      await store.create(
        '001',
        'Nova pessoa',
        f.medium,
        sessionId: f.session,
        guideId: f.guide,
      );
      expect((await store.all()).length, 2);
    } finally {
      await store.db.close();
      await dir.delete(recursive: true);
    }
  });

  test(
    'Sessões isolam dia, presença e senha; ocupação permanece global',
    () async {
      final store = await ConsultationStore.open(
        databaseFactoryFfi,
        inMemoryDatabasePath,
      );
      try {
        final f = await setup(store);
        final c = store.catalog;
        await c.saveMedium(
          id: f.medium,
          name: 'Médium teste',
          degree: 'Dirigente',
          ribbon: 'green',
          nucleoIds: [],
        );
        final n2 = await c.saveNucleo(name: 'Segundo núcleo');
        final s2 = await c.saveSession(
          nucleoId: n2,
          phalanx: phalanxes.first,
          duration: 20,
          limit: 10,
        );
        await expectLater(
          store.create(
            '001',
            'Pessoa',
            f.medium,
            sessionId: s2,
            guideId: f.guide,
          ),
          throwsStateError,
        );
        await c.setPresence(s2, f.medium, true);
        await store.create(
          '001',
          'Pessoa A',
          f.medium,
          sessionId: f.session,
          guideId: f.guide,
        );
        final first = (await store.all()).single['id'] as String;
        await store.start(first);
        await store.create(
          '001',
          'Pessoa B',
          f.medium,
          sessionId: s2,
          guideId: f.guide,
        );
        final second = (await store.all()).first['id'] as String;
        await expectLater(store.start(second), throwsStateError);
        // A tentativa de início falha sem deixar a falange da outra sessão travada.
        expect(
          (await c.sessions()).firstWhere((s) => s['id'] == s2)['locked_at'],
          isNull,
        );
        await store.db.update(
          'sessions',
          {'day': '2000-01-01'},
          where: 'id = ?',
          whereArgs: [f.session],
        );
        await expectLater(
          store.create(
            '002',
            'Pessoa',
            f.medium,
            sessionId: f.session,
            guideId: f.guide,
          ),
          throwsStateError,
        );
        await store.finish(first, 5, 'Mesmo após a virada pode encerrar');
        await store.start(second);
        final today = await c.saveSession(
          nucleoId: f.nucleo,
          phalanx: phalanxes[1],
          duration: 20,
          limit: 10,
        );
        expect(today, isNot(f.session));
        expect(await c.attendance(today), isEmpty);
        expect(
          (await c.sessions()).firstWhere(
            (s) => s['id'] == f.session,
          )['locked_at'],
          isNotNull,
        );
      } finally {
        await store.db.close();
      }
    },
  );

  test('Dia de trabalho vira às 03h e aceita virada de mês', () {
    expect(sessionDay(DateTime(2026, 10, 1, 2, 59)), '2026-09-30');
    expect(sessionDay(DateTime(2026, 10, 1, 3)), '2026-10-01');
  });

  testWidgets('Navega pelos cadastros e cria núcleo na interface', (
    tester,
  ) async {
    final store = (await tester.runAsync(
      () => ConsultationStore.open(databaseFactoryFfi, inMemoryDatabasePath),
    ))!;
    addTearDown(() => tester.runAsync(store.db.close));
    await tester.pumpWidget(CentelhaApp(store: store));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastros e configuração diária'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novo núcleo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Núcleo da interface',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Núcleo da interface'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
