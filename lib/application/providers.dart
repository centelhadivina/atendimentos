import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities.dart';
import '../domain/consultation_access.dart';
import '../domain/failure.dart';
import '../domain/repositories.dart';
import '../domain/use_cases.dart';
import '../data/remote/data_sources.dart';
import '../data/remote/supabase_data_sources.dart';
import '../data/repositories/remote_repositories.dart';

// Composition root: implementações substituíveis sem importar SDK no domínio.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) =>
      throw StateError('Inicialize e injete o cliente Supabase no bootstrap.'),
);
final authDataSourceProvider = Provider<AuthDataSource>(
  (ref) => SupabaseAuthDataSource(ref.watch(supabaseClientProvider)),
);
final catalogDataSourceProvider = Provider<CatalogDataSource>(
  (ref) => SupabaseCatalogDataSource(ref.watch(supabaseClientProvider)),
);
final sessionDataSourceProvider = Provider<SessionDataSource>(
  (ref) => SupabaseSessionDataSource(ref.watch(supabaseClientProvider)),
);
final consultationDataSourceProvider = Provider<ConsultationDataSource>(
  (ref) => SupabaseConsultationDataSource(ref.watch(supabaseClientProvider)),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => RemoteAuthRepository(ref.watch(authDataSourceProvider)),
);
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => RemoteCatalogRepository(ref.watch(catalogDataSourceProvider)),
);
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => RemoteSessionRepository(ref.watch(sessionDataSourceProvider)),
);
final consultationRepositoryProvider = Provider<ConsultationRepository>(
  (ref) =>
      RemoteConsultationRepository(ref.watch(consultationDataSourceProvider)),
);
final saveMediumProvider = Provider(
  (ref) => SaveMedium(ref.watch(catalogRepositoryProvider)),
);
final configureSessionProvider = Provider(
  (ref) => ConfigureSession(ref.watch(sessionRepositoryProvider)),
);
final openConsultationProvider = Provider(
  (ref) => OpenConsultationUseCase(ref.watch(consultationRepositoryProvider)),
);
final finishConsultationProvider = Provider(
  (ref) => FinishConsultation(ref.watch(consultationRepositoryProvider)),
);
final authIdentityProvider = StreamProvider<Identity?>(
  (ref) => ref.watch(authRepositoryProvider).watchIdentity(),
);

Future<void> _authenticated(Ref ref) async {
  if (await ref.watch(authIdentityProvider.future) == null) {
    throw const AppFailure(
      FailureKind.unauthenticated,
      'Entre para continuar.',
    );
  }
}

final profileProvider = FutureProvider.autoDispose<Profile>((ref) async {
  final repository = ref.watch(authRepositoryProvider);
  await _authenticated(ref);
  return repository.profile();
});
final nucleosProvider = FutureProvider.autoDispose<List<Nucleo>>((ref) async {
  final repository = ref.watch(catalogRepositoryProvider);
  await _authenticated(ref);
  return repository.nucleos();
});
final phalanxesProvider = FutureProvider.autoDispose<List<Phalanx>>((
  ref,
) async {
  final repository = ref.watch(catalogRepositoryProvider);
  await _authenticated(ref);
  return repository.phalanxes();
});
final mediumsProvider = FutureProvider.autoDispose.family<List<Medium>, bool>((
  ref,
  includeInactive,
) async {
  final repository = ref.watch(catalogRepositoryProvider);
  await _authenticated(ref);
  return repository.mediums(includeInactive: includeInactive);
});
final currentSessionProvider = FutureProvider.autoDispose
    .family<WorkSession?, String>((ref, nucleoId) async {
      final repository = ref.watch(sessionRepositoryProvider);
      await _authenticated(ref);
      return repository.current(nucleoId);
    });
final attendanceProvider = FutureProvider.autoDispose
    .family<List<Attendance>, String>((ref, sessionId) async {
      final repository = ref.watch(sessionRepositoryProvider);
      await _authenticated(ref);
      return repository.attendance(sessionId);
    });
final consultationsProvider = StreamProvider.autoDispose
    .family<List<Consultation>, String>((ref, sessionId) async* {
      final repository = ref.watch(consultationRepositoryProvider);
      await _authenticated(ref);
      yield* repository.watch(sessionId);
    });

/// Falhas de negócio/autorização exigem ação do usuário; não repetir comandos.
Duration? retryRemoteProvider(int retryCount, Object error) {
  if (error is AppFailure && error.kind != FailureKind.unavailable) return null;
  if (retryCount >= 2) return null;
  return Duration(seconds: 1 << retryCount);
}

final signInConsultationProvider = Provider(
  (ref) => SignInConsultation(ref.watch(authRepositoryProvider)),
);
final quickSignInConsultationProvider = Provider(
  (ref) => QuickSignInConsultation(ref.watch(authRepositoryProvider)),
);
