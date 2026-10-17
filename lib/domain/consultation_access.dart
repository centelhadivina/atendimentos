import 'entities.dart';
import 'failure.dart';
import 'repositories.dart';

const masterAdminEmail = 'cinthiadutra@gmail.com';

/// Só conclui o login quando a conta tem perfil próprio do Consultas.
class SignInConsultation {
  const SignInConsultation(this.repository);
  final AuthRepository repository;
  Future<Identity> call(String email, String password) async {
    final identity = await repository.signIn(email, password);
    try {
      await repository.profile();
      return identity;
    } catch (_) {
      try {
        await repository.signOut();
      } catch (_) {
        /* Preserva a falha original. */
      }
      rethrow;
    }
  }
}

class QuickSignInConsultation {
  const QuickSignInConsultation(this.repository);
  final AuthRepository repository;
  Future<Identity> call(QuickAccessTarget target) async {
    require(target.nucleoId.isNotEmpty, 'Selecione o núcleo.');
    final identity = await repository.quickSignIn(target);
    try {
      final profile = await repository.profile();
      if (profile.role.name != target.role.name ||
          !profile.nucleoIds.contains(target.nucleoId)) {
        throw const AppFailure(
          FailureKind.forbidden,
          'Conta sem acesso a este núcleo e perfil.',
        );
      }
      return identity;
    } catch (_) {
      try {
        await repository.signOut();
      } catch (_) {
        /* Preserva a falha original. */
      }
      rethrow;
    }
  }
}
