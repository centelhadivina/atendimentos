import 'entities.dart';
import 'failure.dart';
import 'repositories.dart';

String normalizePassword(String value) {
  final match = RegExp(r'^([0-9]{1,4})([a-z]?)$')
      .firstMatch(value.trim().toLowerCase());
  require(
    match != null,
    'A senha deve ter de 1 a 4 algarismos e uma letra opcional.',
  );
  return '${int.parse(match![1]!)}${match[2]}';
}

bool isTestConsultation(String name, bool explicit) =>
    explicit ||
    RegExp(
      r'(^|[^a-zà-ÿ])teste([^a-zà-ÿ]|$)',
      caseSensitive: false,
    ).hasMatch(name);

bool canTransition(ConsultationStatus from, ConsultationStatus to) =>
    from == to ||
    switch (from) {
      ConsultationStatus.waiting || ConsultationStatus.queue =>
        to == ConsultationStatus.inProgress ||
            to == ConsultationStatus.cancelled,
      ConsultationStatus.inProgress =>
        to == ConsultationStatus.completed ||
            to == ConsultationStatus.cancelled,
      ConsultationStatus.completed || ConsultationStatus.cancelled => false,
    };

class SaveMedium {
  const SaveMedium(this.repository);
  final CatalogRepository repository;
  Future<Medium> call(MediumDraft draft, List<Phalanx> phalanxes) {
    require(draft.name.trim().isNotEmpty, 'Informe o nome do médium.');
    require(draft.nucleoIds.isNotEmpty, 'Selecione ao menos um núcleo.');
    require(
      draft.guides.every((g) => g.name.trim().isNotEmpty),
      'Preencha os nomes dos guias.',
    );
    final ids = draft.guides.map((g) => g.phalanxId).toSet();
    require(
      ids.length == draft.guides.length,
      'Cadastre somente um guia por falange.',
    );
    require(
      phalanxes
          .where((p) => p.requiredForRegistration)
          .every((p) => ids.contains(p.id)),
      'Cadastre um guia para cada falange obrigatória.',
    );
    require(
      draft.guides.every((g) => phalanxes.any((p) => p.id == g.phalanxId)),
      'Falange desconhecida.',
    );
    return repository.saveMedium(draft);
  }
}

class ConfigureSession {
  const ConfigureSession(this.repository);
  final SessionRepository repository;
  Future<WorkSession> call({
    required String nucleoId,
    required String phalanxId,
    int durationMinutes = 30,
    int consultationLimit = 3,
    String? dirigentId,
  }) {
    require(durationMinutes >= 30, 'A duração mínima é de 30 minutos.');
    require(consultationLimit >= 3, 'O limite mínimo é de 3 consultas.');
    return repository.configure(
      nucleoId: nucleoId,
      phalanxId: phalanxId,
      durationMinutes: durationMinutes,
      consultationLimit: consultationLimit,
      dirigentId: dirigentId,
    );
  }
}

class OpenConsultationUseCase {
  const OpenConsultationUseCase(this.repository);
  final ConsultationRepository repository;
  Future<Consultation> call(OpenConsultation input) {
    require(input.consultantName.trim().isNotEmpty, 'Informe o consulente.');
    if (input.overrideReason != null) {
      require(
        input.overrideReason!
                .trim()
                .split(RegExp(r'\s+'))
                .where((s) => s.isNotEmpty)
                .length >=
            5,
        'A justificativa deve ter pelo menos cinco palavras.',
      );
    }
    return repository.open(
      OpenConsultation(
        sessionId: input.sessionId,
        mediumId: input.mediumId,
        guideId: input.guideId,
        password: normalizePassword(input.password),
        consultantName: input.consultantName.trim(),
        isTest: isTestConsultation(input.consultantName, input.isTest),
        overrideReason: input.overrideReason?.trim(),
      ),
    );
  }
}

class FinishConsultation {
  const FinishConsultation(this.repository);
  final ConsultationRepository repository;
  Future<Consultation> call(String id, int rating, {String comment = ''}) {
    require(rating >= 1 && rating <= 5, 'Avalie de 1 a 5.');
    return repository.finish(id, rating, comment.trim());
  }
}
