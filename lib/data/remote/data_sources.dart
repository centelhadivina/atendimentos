// Contratos técnicos da camada de dados. Nenhum tipo do SDK atravessa esta fronteira.
typedef Json = Map<String, dynamic>;

abstract interface class CatalogDataSource {
  Future<List<Json>> nucleos();
  Future<Json> saveNucleo(Json input);
  Future<List<Json>> phalanxes();
  Future<List<Json>> mediums(bool includeInactive);
  Future<Json> saveMedium(Json input);
  Future<Json> setMediumActive(String id, bool active, String? reason);
}

abstract interface class SessionDataSource {
  Future<Json?> current(String nucleoId);
  Future<Json> configure(Json input);
  Future<List<Json>> attendance(String sessionId);
  Future<Json> setPresence(String sessionId, String mediumId, bool present);
}

abstract interface class ConsultationDataSource {
  Future<List<Json>> list(String sessionId);
  Stream<List<Json>> watch(String sessionId);
  Future<String> suggestPassword(String sessionId, String password);
  Future<Json> open(Json input);
  Future<Json> start(String id);
  Future<Json> transfer(String id, String mediumId, String guideId);
  Future<Json> finish(String id, int rating, String comment);
  Future<Json> cancel(String id);
  Future<List<Json>> findInProgress(String nucleoId, String query);
}

abstract interface class AuthDataSource {
  Json? get currentIdentity;
  Stream<Json?> watchIdentity();
  Future<Json> signIn(String email, String password);
  Future<Json> quickSignIn(String nucleoId, String role);
  Future<Json?> signUp(String name, String email, String password);
  Future<void> signOut();
  Future<Json> profile();
}
