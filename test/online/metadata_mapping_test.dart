import 'package:flutter_test/flutter_test.dart';
import 'package:centelha_consultas/data/remote/mappers.dart';
import 'package:centelha_consultas/domain/entities.dart';

void main() {
  test('Não descarta nomes históricos, dirigente e metadados da fila', () {
    final row = <String, dynamic>{
      'id': 'c',
      'session_id': 's',
      'nucleo_id': 'n',
      'medium_id': 'm',
      'guide_id': 'g',
      'password': '1a',
      'consultant_name': 'Pessoa',
      'status': 'waiting',
      'created_at': '2026-10-16T20:00:00Z',
      'duration_minutes': 30,
      'is_test': false,
      'is_extra': true,
      'exceeded_by': 1,
      'medium_name': 'Nome histórico',
      'guide_name': 'Guia histórico',
      'phalanx_id': 'p',
      'dirigent_id': 'd',
      'dirigent_name': 'Dirigente histórico',
      'queue_position': 2,
      'queued_at': '2026-10-16T20:01:00Z',
      'updated_at': '2026-10-16T20:02:00Z',
      'override_reason': 'Atendimento adicional autorizado pelo dirigente hoje',
    };
    final c = consultationFromJson(row);
    expect(c.mediumName, 'Nome histórico');
    expect(c.guideName, 'Guia histórico');
    expect(c.phalanxId, 'p');
    expect(c.dirigentId, 'd');
    expect(c.dirigentName, 'Dirigente histórico');
    expect(c.classification, 'extra');
    expect(c.queuePosition, 2);
    expect(c.queuedAt, DateTime.utc(2026, 10, 16, 20, 1));
    expect(c.updatedAt, DateTime.utc(2026, 10, 16, 20, 2));
    row.removeWhere(
      (key, _) => {
        'medium_name',
        'guide_name',
        'phalanx_id',
        'dirigent_id',
        'dirigent_name',
        'queue_position',
        'queued_at',
        'updated_at',
      }.contains(key),
    );
    expect(consultationFromJson(row).mediumName, isNull);
  });
  test('Perfil preserva vínculos pessoais e datas sem tipos do SDK', () {
    final profile = profileFromJson({
      'id': 'u',
      'name': 'Pessoa',
      'role': 'medium',
      'email': 'pessoa@example.com',
      'medium_id': 'm',
      'photo_url': 'https://example.com/photo',
      'user_nucleos': [
        {'nucleo_id': 'n'},
      ],
      'created_at': '2026-10-16T20:00:00Z',
    });
    expect(profile.role, UserRole.medium);
    expect(profile.mediumId, 'm');
    expect(profile.nucleoIds, ['n']);
    expect(profile.photoUrl, 'https://example.com/photo');
    expect(profile.createdAt, isNotNull);
    expect(() => profile.nucleoIds.clear(), throwsUnsupportedError);
    expect(
      profileFromJson({'id': 'u', 'name': 'Pessoa', 'role': 'user'}).nucleoIds,
      isEmpty,
    );
  });
}
