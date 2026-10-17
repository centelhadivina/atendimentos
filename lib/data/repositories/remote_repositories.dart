import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../remote/data_sources.dart';
import '../remote/mappers.dart';
import '../remote/remote_call.dart';

class RemoteCatalogRepository implements CatalogRepository {
  const RemoteCatalogRepository(this.source);
  final CatalogDataSource source;
  @override
  Future<List<Nucleo>> nucleos() => remoteCall(
    () async => (await source.nucleos()).map(nucleoFromJson).toList(),
  );
  @override
  Future<Nucleo> saveNucleo({
    String? id,
    required String name,
    String description = '',
    String? code,
    String? abbreviation,
  }) => remoteCall(
    () async => nucleoFromJson(
      await source.saveNucleo({
        'id': id,
        'name': name.trim(),
        'description': description.trim(),
        'code': code?.trim(),
        'abbreviation': abbreviation?.trim(),
      }),
    ),
  );
  @override
  Future<List<Phalanx>> phalanxes() => remoteCall(
    () async => (await source.phalanxes()).map(phalanxFromJson).toList(),
  );
  @override
  Future<List<Medium>> mediums({bool includeInactive = false}) => remoteCall(
    () async =>
        (await source.mediums(includeInactive)).map(mediumFromJson).toList(),
  );
  @override
  Future<Medium> saveMedium(MediumDraft draft) => remoteCall(
    () async => mediumFromJson(await source.saveMedium(mediumToJson(draft))),
  );
  @override
  Future<Medium> setMediumActive(String id, bool active, {String? reason}) =>
      remoteCall(
        () async => mediumFromJson(
          await source.setMediumActive(id, active, reason?.trim()),
        ),
      );
}

class RemoteSessionRepository implements SessionRepository {
  const RemoteSessionRepository(this.source);
  final SessionDataSource source;
  @override
  Future<WorkSession?> current(String nucleoId) => remoteCall(() async {
    final row = await source.current(nucleoId);
    return row == null ? null : sessionFromJson(row);
  });
  @override
  Future<WorkSession> configure({
    required String nucleoId,
    required String phalanxId,
    int durationMinutes = 30,
    int consultationLimit = 3,
    String? dirigentId,
  }) => remoteCall(
    () async => sessionFromJson(
      await source.configure({
        'nucleo_id': nucleoId,
        'phalanx_id': phalanxId,
        'duration_minutes': durationMinutes,
        'consultation_limit': consultationLimit,
        'dirigent_id': dirigentId,
      }),
    ),
  );
  @override
  Future<List<Attendance>> attendance(String sessionId) => remoteCall(
    () async =>
        (await source.attendance(sessionId)).map(attendanceFromJson).toList(),
  );
  @override
  Future<Attendance> setPresence(
    String sessionId,
    String mediumId,
    bool present,
  ) => remoteCall(
    () async => attendanceFromJson(
      await source.setPresence(sessionId, mediumId, present),
    ),
  );
}

class RemoteConsultationRepository implements ConsultationRepository {
  const RemoteConsultationRepository(this.source);
  final ConsultationDataSource source;
  @override
  Future<List<Consultation>> list(String sessionId) => remoteCall(
    () async =>
        (await source.list(sessionId)).map(consultationFromJson).toList(),
  );
  @override
  Stream<List<Consultation>> watch(String sessionId) => remoteStream(
    source
        .watch(sessionId)
        .map(
          (rows) => rows.map(consultationFromJson).toList()
            ..sort((a, b) {
              final order = a.createdAt.compareTo(b.createdAt);
              return order == 0 ? a.id.compareTo(b.id) : order;
            }),
        ),
  );
  @override
  Future<String> suggestPassword(String sessionId, String password) =>
      remoteCall(() => source.suggestPassword(sessionId, password));
  @override
  Future<Consultation> open(OpenConsultation input) => remoteCall(
    () async => consultationFromJson(await source.open(openToJson(input))),
  );
  @override
  Future<Consultation> start(String id) =>
      remoteCall(() async => consultationFromJson(await source.start(id)));
  @override
  Future<Consultation> transfer(String id, String mediumId, String guideId) =>
      remoteCall(
        () async =>
            consultationFromJson(await source.transfer(id, mediumId, guideId)),
      );
  @override
  Future<Consultation> finish(String id, int rating, String comment) =>
      remoteCall(
        () async =>
            consultationFromJson(await source.finish(id, rating, comment)),
      );
  @override
  Future<Consultation> cancel(String id) =>
      remoteCall(() async => consultationFromJson(await source.cancel(id)));
  @override
  Future<List<Consultation>> findInProgress(String nucleoId, String query) =>
      remoteCall(
        () async => (await source.findInProgress(
          nucleoId,
          query.trim(),
        )).map(consultationFromJson).toList(),
      );
}

class RemoteAuthRepository implements AuthRepository {
  const RemoteAuthRepository(this.source);
  final AuthDataSource source;
  @override
  Identity? get currentIdentity {
    final user = source.currentIdentity;
    return user == null ? null : identityFromJson(user);
  }

  @override
  Stream<Identity?> watchIdentity() => remoteStream(
    source.watchIdentity().map((j) => j == null ? null : identityFromJson(j)),
  );
  @override
  Future<Identity> signIn(String email, String password) => remoteCall(
    () async => identityFromJson(await source.signIn(email.trim(), password)),
  );
  @override
  Future<Identity> quickSignIn(QuickAccessTarget target) => remoteCall(
    () async => identityFromJson(
      await source.quickSignIn(target.nucleoId, target.role.name),
    ),
  );
  @override
  Future<Identity?> signUp(String name, String email, String password) =>
      remoteCall(() async {
        final row = await source.signUp(name.trim(), email.trim(), password);
        return row == null ? null : identityFromJson(row);
      });
  @override
  Future<void> signOut() => remoteCall(source.signOut);
  @override
  Future<Profile> profile() =>
      remoteCall(() async => profileFromJson(await source.profile()));
}
