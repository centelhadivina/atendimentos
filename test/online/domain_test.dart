import 'package:flutter_test/flutter_test.dart';
import 'package:centelha_consultas/domain/entities.dart';
import 'package:centelha_consultas/domain/failure.dart';
import 'package:centelha_consultas/domain/repositories.dart';
import 'package:centelha_consultas/domain/use_cases.dart';
import 'package:centelha_consultas/core/supabase_config.dart';

class CapturingConsultationRepository implements ConsultationRepository {
  OpenConsultation? captured;
  @override
  Future<Consultation> open(OpenConsultation input) async {
    captured = input;
    throw const AppFailure(FailureKind.unavailable, 'Servidor indisponível');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RejectingCatalogRepository implements CatalogRepository {
  bool called = false;
  @override
  Future<Medium> saveMedium(MediumDraft draft) async {
    called = true;
    throw StateError('Chamou persistência');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RejectingSessionRepository implements SessionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Normaliza senha sem perder sufixo; recusa caracteres e excesso', () {
    expect(normalizePassword(' 0001A '), '1a');
    expect(normalizePassword('0000'), '0');
    expect(normalizePassword('9999z'), '9999z');
    for (final value in ['', '12345', '-1', '1aa', '1.0', 'a1']) {
      expect(() => normalizePassword(value), throwsA(isA<AppFailure>()));
    }
  });
  test('Identifica teste como palavra, não como parte de outra palavra', () {
    expect(isTestConsultation('Pessoa TESTE de fluxo', false), true);
    expect(isTestConsultation('Pessoa (teste)', false), true);
    expect(isTestConsultation('Pessoa', true), true);
    expect(isTestConsultation('Pessoa Testemunha', false), false);
  });
  test('State machine preserva terminais e permite idempotência', () {
    for (final status in ConsultationStatus.values) {
      expect(canTransition(status, status), true);
    }
    for (final terminal in [
      ConsultationStatus.completed,
      ConsultationStatus.cancelled,
    ]) {
      for (final target in ConsultationStatus.values.where(
        (s) => s != terminal,
      )) {
        expect(canTransition(terminal, target), false);
      }
    }
    expect(
      canTransition(ConsultationStatus.waiting, ConsultationStatus.completed),
      false,
    );
    expect(
      canTransition(ConsultationStatus.queue, ConsultationStatus.inProgress),
      true,
    );
    expect(
      canTransition(
        ConsultationStatus.inProgress,
        ConsultationStatus.cancelled,
      ),
      true,
    );
  });
  test('Caso de uso aplica mínimos 30/3 antes de acessar repositório', () {
    final configure = ConfigureSession(RejectingSessionRepository());
    expect(
      () => configure(nucleoId: 'n', phalanxId: 'p', durationMinutes: 29),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => configure(nucleoId: 'n', phalanxId: 'p', consultationLimit: 2),
      throwsA(isA<AppFailure>()),
    );
  });
  test('Cadastro exige núcleo, cobertura das falanges e guia único', () {
    final repo = RejectingCatalogRepository();
    final save = SaveMedium(repo);
    final phalanxes = List.generate(
      7,
      (i) =>
          Phalanx(id: '$i', name: 'Falange $i', requiredForRegistration: true),
    );
    MediumDraft draft(
      List<GuideDraft> guides, {
      List<String> nucleoIds = const ['n'],
    }) => MediumDraft(
      name: 'Médium',
      degree: MediumDegree.medium,
      ribbon: Ribbon.green,
      nucleoIds: nucleoIds,
      guides: guides,
    );
    final guides = List.generate(
      7,
      (i) => GuideDraft(name: 'Guia $i', phalanxId: '$i'),
    );
    expect(
      () => save(draft(guides, nucleoIds: []), phalanxes),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => save(draft(guides.take(6).toList()), phalanxes),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => save(draft([...guides, guides.first]), phalanxes),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.called, false);
    expect(() => draft(guides).guides.clear(), throwsUnsupportedError);
  });
  test(
    'Abertura normaliza dados e propaga falha remota sem fallback SQLite',
    () async {
      final repo = CapturingConsultationRepository();
      final open = OpenConsultationUseCase(repo);
      await expectLater(
        open(
          const OpenConsultation(
            sessionId: 's',
            mediumId: 'm',
            guideId: 'g',
            password: '0001',
            consultantName: ' Pessoa teste ',
          ),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.captured!.password, '1');
      expect(repo.captured!.consultantName, 'Pessoa teste');
      expect(repo.captured!.isTest, true);
      expect(
        () => open(
          const OpenConsultation(
            sessionId: 's',
            mediumId: 'm',
            guideId: 'g',
            password: '2',
            consultantName: 'Pessoa',
            overrideReason: 'Poucas palavras',
          ),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => FinishConsultation(repo)('c', 0),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test('Configuração aceita chave pública e recusa service_role/segredos', () {
    const SupabaseConfig(
      url: 'https://project.supabase.co',
      publishableKey: 'sb_publishable_test',
    ).validate();
    expect(
      () => const SupabaseConfig(url: '', publishableKey: '').validate(),
      throwsFormatException,
    );
    expect(
      () => const SupabaseConfig(
        url: 'http://public.example',
        publishableKey: 'sb_publishable_test',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const SupabaseConfig(
        url: 'https://project.supabase.co',
        publishableKey: 'sb_secret_never',
      ).validate(),
      throwsFormatException,
    );
  });
}
