import 'package:flutter_test/flutter_test.dart';
import 'package:centelha_consultas/app/routing/route_catalog.dart';
import 'package:centelha_consultas/domain/entities.dart';

void main() {
  test('Preserva todos os caminhos do mapa, sem registrar telas fictícias', () {
    expect(AppRoute.values.map((r) => r.path).toSet(), {
      '/login',
      '/nucleos',
      '/',
      '/profile',
      '/setup',
      '/mediums',
      '/consultation',
      '/consultation-room',
      '/feedback',
      '/medium-stats',
      '/registration',
      '/history',
      '/admin',
      '/stats',
      '/reports',
    });
    expect(AppRoute.fromPath('/ausente'), isNull);
    expect(AppRoute.fromPath('/consultation-room'), AppRoute.consultationRoom);
  });
  test('Menu e guard são contratos diferentes no original', () {
    expect(AppRoute.consultation.allowsRole(UserRole.medium), true);
    expect(appMenu.any((i) => i.route == AppRoute.consultation), false);
    expect(
      appMenu.where((i) => i.roles.contains(UserRole.user)).map((i) => i.route),
      [
        AppRoute.home,
        AppRoute.setup,
        AppRoute.mediums,
        AppRoute.consultationRoom,
      ],
    );
    expect(AppRoute.feedback.allowsRole(UserRole.user), true);
    expect(AppRoute.mediumStats.allowsRole(UserRole.admin), false);
    expect(AppRoute.mediumStats.allowsRole(UserRole.medium), true);
    expect(AppRoute.registration.allowsRole(UserRole.user), false);
  });
  test('Núcleo é exigido antes do redirecionamento de tablet no início', () {
    expect(
      legacyRouteRedirect(
        AppRoute.home,
        authenticated: false,
        hasNucleo: false,
      ),
      AppRoute.login,
    );
    expect(
      legacyRouteRedirect(
        AppRoute.home,
        authenticated: true,
        role: UserRole.tablet,
        hasNucleo: false,
      ),
      AppRoute.nucleos,
    );
    expect(
      legacyRouteRedirect(
        AppRoute.home,
        authenticated: true,
        role: UserRole.tablet,
        hasNucleo: true,
      ),
      AppRoute.feedback,
    );
    for (final target in [
      AppRoute.feedback,
      AppRoute.profile,
      AppRoute.admin,
      AppRoute.nucleos,
    ]) {
      expect(
        legacyRouteRedirect(
          target,
          authenticated: true,
          role: UserRole.admin,
          hasNucleo: false,
        ),
        isNull,
      );
    }
    expect(
      legacyRouteRedirect(null, authenticated: false, hasNucleo: false),
      isNull,
    );
  });
  test('Distingue os dois destinos pós-login do original', () {
    expect(afterLogin(UserRole.user), AppRoute.home);
    expect(continueFromLogin(UserRole.user), AppRoute.consultationRoom);
    expect(afterLogin(UserRole.tablet), AppRoute.feedback);
    expect(continueFromLogin(UserRole.tablet), AppRoute.feedback);
  });
}
