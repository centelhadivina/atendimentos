import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:centelha_consultas/data/remote/supabase_data_sources.dart';
import 'package:centelha_consultas/data/repositories/remote_repositories.dart';
import 'package:centelha_consultas/domain/entities.dart';
import 'package:centelha_consultas/domain/failure.dart';

final consultationRow = <String, dynamic>{
  'id': 'c',
  'session_id': 's',
  'nucleo_id': 'n',
  'medium_id': 'm',
  'guide_id': 'g',
  'password': '1',
  'consultant_name': 'Pessoa',
  'status': 'in_progress',
  'created_at': '2026-10-16T21:00:00Z',
  'started_at': '2026-10-16T21:00:00Z',
  'ended_at': null,
  'duration_minutes': 30,
  'is_test': false,
  'is_extra': false,
  'exceeded_by': 0,
  'rating': null,
  'feedback': null,
};
http.Response jsonResponse(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
SupabaseClient clientFor(
  Future<http.Response> Function(http.Request) handler,
) => SupabaseClient(
  'https://test.supabase.co',
  'sb_publishable_test',
  httpClient: MockClient((request) async {
    final response = await handler(request);
    return http.Response.bytes(
      response.bodyBytes,
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }),
  authOptions: const AuthClientOptions(
    autoRefreshToken: false,
    authFlowType: AuthFlowType.implicit,
  ),
  postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
);

void main() {
  test('Acesso rápido envia só núcleo/perfil e instala a sessão pelo refresh token', () async {
    final user = {
      'id': '10000000-0000-0000-0000-000000000003',
      'email': 'tecnologia.ccu@gmail.com',
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-10-16T20:00:00Z',
    };
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': user['id'], 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c2ln';
    final client = clientFor((request) async {
      if (request.url.path.endsWith(
        '/functions/v1/consultation-quick-access',
      )) {
        expect(jsonDecode(request.body), {
          'nucleo_id': '001',
          'role': 'tablet',
        });
        expect(request.body.contains('password'), false);
        return jsonResponse({'refresh_token': 'synthetic-refresh'});
      }
      expect(request.url.path, '/auth/v1/token');
      expect(request.url.queryParameters['grant_type'], 'refresh_token');
      expect(
        (jsonDecode(request.body) as Map)['refresh_token'],
        'synthetic-refresh',
      );
      return jsonResponse({
        'access_token': token,
        'refresh_token': 'rotated-refresh',
        'expires_in': 3600,
        'token_type': 'bearer',
        'user': user,
      });
    });
    addTearDown(client.dispose);
    final identity = await RemoteAuthRepository(SupabaseAuthDataSource(client))
        .quickSignIn(
          const QuickAccessTarget(
            nucleoId: '001',
            role: QuickAccessRole.tablet,
          ),
        );
    expect(identity.email, 'tecnologia.ccu@gmail.com');
    expect(client.auth.currentUser?.id, user['id']);
  });

  test('Núcleos compartilhados usam RPC e preservam código/sigla sem converter para UUID', () async {
    final client = clientFor((request) async {
      if (request.url.path.endsWith('list_consultation_nucleos')) {
        return jsonResponse([
          {
            'id': '001',
            'code': '001',
            'abbreviation': 'CD',
            'name': 'Núcleo',
            'description': '',
            'active': true,
          },
        ]);
      }
      expect(request.url.path, '/rest/v1/rpc/save_nucleo');
      final data = (jsonDecode(request.body) as Map)['p_data'] as Map;
      expect(data['code'], '002');
      expect(data['abbreviation'], 'NA');
      return jsonResponse({
        'id': '002',
        'code': '002',
        'abbreviation': 'NA',
        'name': 'Novo núcleo',
        'description': 'Descrição',
        'active': true,
      });
    });
    addTearDown(client.dispose);
    final repository = RemoteCatalogRepository(
      SupabaseCatalogDataSource(client),
    );
    final existing = (await repository.nucleos()).single;
    expect(existing.id, '001');
    expect(existing.code, '001');
    expect(existing.abbreviation, 'CD');
    final created = await repository.saveNucleo(
      name: 'Novo núcleo',
      code: '002',
      abbreviation: 'NA',
      description: 'Descrição',
    );
    expect(created.id, '002');
  });

  test('Cadastro Auth preserva confirmação de e-mail e não atribui papel no cliente', () async {
    final client = clientFor((request) async {
      expect(request.url.path, '/auth/v1/signup');
      final body = jsonDecode(request.body) as Map;
      expect(body['email'], 'pessoa@example.com');
      expect(body['data'], {'name': 'Pessoa'});
      return jsonResponse({
        'id': '10000000-0000-0000-0000-000000000002',
        'aud': 'authenticated',
        'email': 'pessoa@example.com',
        'created_at': '2026-10-16T21:00:00Z',
        'app_metadata': {},
        'user_metadata': {'name': 'Pessoa'},
      });
    });
    addTearDown(client.dispose);
    final repository = RemoteAuthRepository(SupabaseAuthDataSource(client));
    expect(
      await repository.signUp('Pessoa', 'pessoa@example.com', 'test-password'),
      isNull,
    );
    expect(repository.currentIdentity, isNull);
  });

  test(
    'SDK envia abertura por RPC e repositório devolve entidade tipada',
    () async {
      final client = clientFor((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rest/v1/rpc/open_consultation');
        final body = jsonDecode(request.body) as Map;
        expect(body['p_data']['session_id'], 's');
        expect(body['p_data']['password'], '1');
        expect(request.headers['apikey'], 'sb_publishable_test');
        return jsonResponse(consultationRow);
      });
      addTearDown(client.dispose);
      final repo = RemoteConsultationRepository(
        SupabaseConsultationDataSource(client),
      );
      final result = await repo.open(
        const OpenConsultation(
          sessionId: 's',
          mediumId: 'm',
          guideId: 'g',
          password: '1',
          consultantName: 'Pessoa',
        ),
      );
      expect(result.status, ConsultationStatus.inProgress);
      expect(result.startedAt!.isUtc, true);
    },
  );
  test(
    'Leitura filtra sessão, ordena fila e observação faz consulta autoritativa',
    () async {
      final client = clientFor((request) async {
        expect(request.url.path, '/rest/v1/consultations');
        expect(request.url.queryParameters['session_id'], 'eq.s');
        expect(request.url.queryParameters['order'], contains('created_at'));
        return jsonResponse([consultationRow]);
      });
      addTearDown(client.dispose);
      final repo = RemoteConsultationRepository(
        SupabaseConsultationDataSource(client),
      );
      expect((await repo.list('s')).single.id, 'c');
      expect((await repo.watch('s').first).single.id, 'c');
    },
  );
  test(
    'Cadastro grava agregado e lê vínculos/guias pela relação Supabase',
    () async {
      final client = clientFor((request) async {
        if (request.url.path.endsWith('/rpc/save_medium')) {
          final data = (jsonDecode(request.body) as Map)['p_data'] as Map;
          expect(data['degree'], 'medium');
          expect(data['nucleo_ids'], ['n']);
          expect(data['guides'][0]['phalanx_id'], 'p');
          return jsonResponse({'id': 'm'});
        }
        expect(request.url.queryParameters['select'], contains('guides(*)'));
        return jsonResponse({
          'id': 'm',
          'name': 'Médium',
          'degree': 'medium',
          'ribbon': 'green',
          'active': true,
          'guides': [
            {'id': 'g', 'medium_id': 'm', 'name': 'Guia', 'phalanx_id': 'p'},
          ],
          'medium_nucleos': [
            {'nucleo_id': 'n'},
          ],
        });
      });
      addTearDown(client.dispose);
      final repo = RemoteCatalogRepository(SupabaseCatalogDataSource(client));
      final m = await repo.saveMedium(
        MediumDraft(
          name: 'Médium',
          degree: MediumDegree.medium,
          ribbon: Ribbon.green,
          nucleoIds: ['n'],
          guides: [const GuideDraft(name: 'Guia', phalanxId: 'p')],
        ),
      );
      expect(m.nucleoIds, ['n']);
      expect(m.guides.single.mediumId, m.id);
    },
  );
  test(
    'Configuração usa RPC com valores 30/3 e suporta sessão inexistente',
    () async {
      final client = clientFor((request) async {
        if (request.url.path.endsWith('current_work_session')) {
          return jsonResponse(null);
        }
        expect(
          (jsonDecode(request.body) as Map)['p_data']['duration_minutes'],
          30,
        );
        return jsonResponse({
          'id': 's',
          'nucleo_id': 'n',
          'work_day': '2026-10-16',
          'phalanx_id': 'p',
          'duration_minutes': 30,
          'consultation_limit': 3,
          'dirigent_id': null,
          'locked_at': null,
        });
      });
      addTearDown(client.dispose);
      final repo = RemoteSessionRepository(SupabaseSessionDataSource(client));
      expect(await repo.current('n'), isNull);
      expect(
        (await repo.configure(nucleoId: 'n', phalanxId: 'p')).consultationLimit,
        3,
      );
    },
  );
  test(
    'Falhas de permissão, conflito e negócio não vazam detalhes do SDK',
    () async {
      for (final entry in {
        '42501': FailureKind.forbidden,
        '23505': FailureKind.conflict,
        'P0001': FailureKind.validation,
      }.entries) {
        final client = clientFor(
          (_) async => jsonResponse({
            'code': entry.key,
            'message': 'Mensagem do banco',
            'details': null,
            'hint': null,
          }, 400),
        );
        final repo = RemoteConsultationRepository(
          SupabaseConsultationDataSource(client),
        );
        await expectLater(
          repo.start('c'),
          throwsA(isA<AppFailure>().having((e) => e.kind, 'kind', entry.value)),
        );
        await client.dispose();
      }
    },
  );
  test(
    'Erro HTTP é indisponibilidade; não há sucesso ou lista vazia fictícios',
    () async {
      final client = clientFor(
        (_) async => throw http.ClientException('network'),
      );
      addTearDown(client.dispose);
      final repo = RemoteConsultationRepository(
        SupabaseConsultationDataSource(client),
      );
      await expectLater(
        repo.list('s'),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.unavailable,
          ),
        ),
      );
    },
  );
}
