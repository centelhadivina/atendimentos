import 'package:flutter_test/flutter_test.dart';
import 'package:centelha_consultas/domain/consultation_access.dart';
import 'package:centelha_consultas/domain/entities.dart';
import 'package:centelha_consultas/domain/failure.dart';
import 'package:centelha_consultas/domain/repositories.dart';

class FakeAuthRepository implements AuthRepository {
  int logouts = 0, logins = 0;
  bool failProfile = false;
  Profile value = Profile(
    id: 'u',
    name: 'Tablet',
    role: UserRole.tablet,
    nucleoIds: ['001'],
  );
  @override
  Future<Identity> signIn(String email, String password) async {
    logins++;
    return Identity('u', email);
  }

  @override
  Future<Identity> quickSignIn(QuickAccessTarget target) async {
    logins++;
    return const Identity('u', 'tablet@example.com');
  }

  @override
  Future<Profile> profile() async {
    if (failProfile) {
      throw const AppFailure(FailureKind.forbidden, 'Conta não autorizada.');
    }
    return value;
  }

  @override
  Future<void> signOut() async {
    logouts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Acesso rápido confirma papel/núcleo sem receber senha no caso de uso',
    () async {
      final repo = FakeAuthRepository();
      final identity = await QuickSignInConsultation(repo)(
        const QuickAccessTarget(nucleoId: '001', role: QuickAccessRole.tablet),
      );
      expect(identity.id, 'u');
      expect(repo.logouts, 0);
    },
  );
  test('Não aceita conta de outro núcleo ou papel para o atalho', () async {
    final repo = FakeAuthRepository();
    await expectLater(
      QuickSignInConsultation(repo)(
        const QuickAccessTarget(nucleoId: '002', role: QuickAccessRole.tablet),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.logouts, 1);
    await expectLater(
      QuickSignInConsultation(repo)(
        const QuickAccessTarget(nucleoId: '001', role: QuickAccessRole.cambono),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.logouts, 2);
  });
  test('Login válido no Auth mas não no Consultas encerra somente a sessão iniciada', () async {
    final repo = FakeAuthRepository()..failProfile = true;
    await expectLater(
      SignInConsultation(repo)('claudia@example.com', 'transient'),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.logouts, 1);
  });
  test('Seleção de núcleo é obrigatória antes de autenticar', () async {
    final repo = FakeAuthRepository();
    await expectLater(
      QuickSignInConsultation(repo)(
        const QuickAccessTarget(nucleoId: '', role: QuickAccessRole.tablet),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.logins, 0);
  });
}
