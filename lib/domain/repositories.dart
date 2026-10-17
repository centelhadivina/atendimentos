import 'entities.dart';

abstract interface class AuthRepository {
  Identity? get currentIdentity;
  Stream<Identity?> watchIdentity();
  Future<Identity> signIn(String email, String password);
  Future<Identity> quickSignIn(QuickAccessTarget target);

  /// Pode retornar null quando a confirmação de e-mail é necessária.
  Future<Identity?> signUp(String name, String email, String password);
  Future<void> signOut();
  Future<Profile> profile();
}

abstract interface class CatalogRepository {
  Future<List<Nucleo>> nucleos();
  Future<Nucleo> saveNucleo({
    String? id,
    required String name,
    String description = '',
    String? code,
    String? abbreviation,
  });
  Future<List<Phalanx>> phalanxes();
  Future<List<Medium>> mediums({bool includeInactive = false});
  Future<Medium> saveMedium(MediumDraft draft);
  Future<Medium> setMediumActive(String id, bool active, {String? reason});
}

abstract interface class SessionRepository {
  Future<WorkSession?> current(String nucleoId);
  Future<WorkSession> configure({
    required String nucleoId,
    required String phalanxId,
    int durationMinutes = 30,
    int consultationLimit = 3,
    String? dirigentId,
  });
  Future<List<Attendance>> attendance(String sessionId);
  Future<Attendance> setPresence(
    String sessionId,
    String mediumId,
    bool present,
  );
}

abstract interface class ConsultationRepository {
  Future<List<Consultation>> list(String sessionId);
  Stream<List<Consultation>> watch(String sessionId);
  Future<String> suggestPassword(String sessionId, String password);
  Future<Consultation> open(OpenConsultation input);
  Future<Consultation> start(String id);
  Future<Consultation> transfer(String id, String mediumId, String guideId);
  Future<Consultation> finish(String id, int rating, String comment);
  Future<Consultation> cancel(String id);
  Future<List<Consultation>> findInProgress(String nucleoId, String query);
}
