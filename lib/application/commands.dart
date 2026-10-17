import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities.dart';
import 'providers.dart';

/// Estado de envio separado dos providers de leitura. Erros chegam ao chamador
/// e ao AsyncValue, permitindo que a futura interface preserve o formulário.
abstract class AsyncCommand extends AsyncNotifier<void> {
  @override
  void build() {}
  Future<T> execute<T>(Future<T> Function() operation) async {
    state = const AsyncLoading();
    try {
      final result = await operation();
      if (ref.mounted) state = const AsyncData(null);
      return result;
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
      rethrow;
    }
  }
}

final authCommandsProvider = AsyncNotifierProvider<AuthCommands, void>(
  AuthCommands.new,
);

class AuthCommands extends AsyncCommand {
  Future<Identity> signIn(String email, String password) =>
      execute(() => ref.read(signInConsultationProvider)(email, password));
  Future<Identity> quickSignIn(QuickAccessTarget target) =>
      execute(() => ref.read(quickSignInConsultationProvider)(target));
  Future<void> signOut() =>
      execute(() => ref.read(authRepositoryProvider).signOut());
}

final catalogCommandsProvider = AsyncNotifierProvider<CatalogCommands, void>(
  CatalogCommands.new,
);

class CatalogCommands extends AsyncCommand {
  Future<Nucleo> saveNucleo({
    String? id,
    required String name,
    String description = '',
    String? code,
    String? abbreviation,
  }) => execute(() async {
    final result = await ref
        .read(catalogRepositoryProvider)
        .saveNucleo(
          id: id,
          name: name,
          description: description,
          code: code,
          abbreviation: abbreviation,
        );
    if (ref.mounted) ref.invalidate(nucleosProvider);
    return result;
  });
  Future<Medium> saveMedium(MediumDraft draft, List<Phalanx> phalanxes) =>
      execute(() async {
        final result = await ref.read(saveMediumProvider)(draft, phalanxes);
        if (ref.mounted) ref.invalidate(mediumsProvider);
        return result;
      });
  Future<Medium> setMediumActive(String id, bool active, {String? reason}) =>
      execute(() async {
        final result = await ref
            .read(catalogRepositoryProvider)
            .setMediumActive(id, active, reason: reason);
        if (ref.mounted) {
          ref.invalidate(mediumsProvider);
          ref.invalidate(attendanceProvider);
        }
        return result;
      });
}

final sessionCommandsProvider = AsyncNotifierProvider<SessionCommands, void>(
  SessionCommands.new,
);

class SessionCommands extends AsyncCommand {
  Future<WorkSession> configure({
    required String nucleoId,
    required String phalanxId,
    int durationMinutes = 30,
    int consultationLimit = 3,
    String? dirigentId,
  }) => execute(() async {
    final result = await ref.read(configureSessionProvider)(
      nucleoId: nucleoId,
      phalanxId: phalanxId,
      durationMinutes: durationMinutes,
      consultationLimit: consultationLimit,
      dirigentId: dirigentId,
    );
    if (ref.mounted) ref.invalidate(currentSessionProvider(nucleoId));
    return result;
  });
  Future<Attendance> setPresence(
    String sessionId,
    String mediumId,
    bool present,
  ) => execute(() async {
    final result = await ref
        .read(sessionRepositoryProvider)
        .setPresence(sessionId, mediumId, present);
    if (ref.mounted) ref.invalidate(attendanceProvider(sessionId));
    return result;
  });
}

final consultationCommandsProvider =
    AsyncNotifierProvider<ConsultationCommands, void>(ConsultationCommands.new);

class ConsultationCommands extends AsyncCommand {
  Future<Consultation> _change(Future<Consultation> Function() operation) =>
      execute(() async {
        final result = await operation();
        if (ref.mounted) {
          ref.invalidate(consultationsProvider(result.sessionId));
          ref.invalidate(currentSessionProvider(result.nucleoId));
        }
        return result;
      });
  Future<Consultation> open(OpenConsultation input) =>
      _change(() => ref.read(openConsultationProvider)(input));
  Future<Consultation> start(String id) =>
      _change(() => ref.read(consultationRepositoryProvider).start(id));
  Future<Consultation> transfer(String id, String mediumId, String guideId) =>
      _change(
        () => ref
            .read(consultationRepositoryProvider)
            .transfer(id, mediumId, guideId),
      );
  Future<Consultation> finish(String id, int rating, {String comment = ''}) =>
      _change(
        () =>
            ref.read(finishConsultationProvider)(id, rating, comment: comment),
      );
  Future<Consultation> cancel(String id) =>
      _change(() => ref.read(consultationRepositoryProvider).cancel(id));
}
