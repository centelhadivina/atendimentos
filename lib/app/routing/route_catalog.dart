import '../../domain/entities.dart';

/// Contrato de paridade de navegação com o React. Não registra telas prontas
/// nem substitui a autorização dos repositórios/Supabase.
enum AppRoute {
  login('/login'),
  nucleos('/nucleos'),
  home('/'),
  profile('/profile'),
  setup('/setup'),
  mediums('/mediums'),
  consultation('/consultation'),
  consultationRoom('/consultation-room'),
  feedback('/feedback'),
  mediumStats('/medium-stats'),
  registration('/registration'),
  history('/history'),
  admin('/admin'),
  stats('/stats'),
  reports('/reports');

  const AppRoute(this.path);
  final String path;

  static AppRoute? fromPath(String path) {
    for (final route in values) {
      if (route.path == path) return route;
    }
    return null;
  }

  bool get requiresAuthentication => this != login;
  bool get requiresNucleo => const {
    home,
    setup,
    mediums,
    consultation,
    consultationRoom,
    registration,
    history,
    stats,
    reports,
  }.contains(this);

  bool get usesMainLayout => this != login && this != profile;

  /// Reproduz o RoleGuard observado, incluindo a equivalência de nível entre
  /// cambono e medium. A tela de estatísticas exige medium exato.
  bool allowsRole(UserRole role) {
    if (this == mediumStats) return role == UserRole.medium;
    final level = switch (role) {
      UserRole.admin => 4,
      UserRole.user => 3,
      UserRole.cambono || UserRole.medium => 2,
      UserRole.tablet => 1,
    };
    return switch (this) {
      setup || mediums || consultation || consultationRoom => level >= 2,
      registration || history || admin || stats || reports => level >= 4,
      _ => true,
    };
  }
}

class AppMenuItem {
  const AppMenuItem(this.route, this.label, this.roles);
  final AppRoute route;
  final String label;
  final Set<UserRole> roles;
}

const appMenu = [
  AppMenuItem(AppRoute.home, 'Início', {...UserRole.values}),
  AppMenuItem(AppRoute.setup, 'Configuração', {
    UserRole.admin,
    UserRole.user,
    UserRole.cambono,
  }),
  AppMenuItem(AppRoute.mediums, 'Presença de Médiuns', {
    UserRole.admin,
    UserRole.user,
    UserRole.cambono,
  }),
  AppMenuItem(AppRoute.consultationRoom, 'Sala de Consultas', {
    UserRole.admin,
    UserRole.user,
    UserRole.cambono,
  }),
  AppMenuItem(AppRoute.feedback, 'Feedback', {
    UserRole.admin,
    UserRole.tablet,
    UserRole.cambono,
  }),
  AppMenuItem(AppRoute.mediumStats, 'Minhas Estatísticas', {UserRole.medium}),
  AppMenuItem(AppRoute.registration, 'Registro de Médiuns', {UserRole.admin}),
  AppMenuItem(AppRoute.history, 'Histórico', {UserRole.admin}),
  AppMenuItem(AppRoute.admin, 'Administração', {UserRole.admin}),
  AppMenuItem(AppRoute.stats, 'Estatísticas Globais', {UserRole.admin}),
  AppMenuItem(AppRoute.reports, 'Relatórios', {UserRole.admin}),
];

AppRoute afterLogin(UserRole role) =>
    role == UserRole.tablet ? AppRoute.feedback : AppRoute.home;
AppRoute continueFromLogin(UserRole role) => switch (role) {
  UserRole.tablet => AppRoute.feedback,
  UserRole.user => AppRoute.consultationRoom,
  _ => AppRoute.home,
};

/// O 404 permanece público. O chamador ainda precisa carregar a seleção de
/// núcleo antes de avaliar este contrato; não há redirecionamento durante loading.
AppRoute? legacyRouteRedirect(
  AppRoute? target, {
  required bool authenticated,
  UserRole? role,
  required bool hasNucleo,
}) {
  if (target == null) return null;
  if (target.requiresAuthentication && !authenticated) return AppRoute.login;
  if (target.requiresNucleo && !hasNucleo) return AppRoute.nucleos;
  if (target == AppRoute.home && role == UserRole.tablet) {
    return AppRoute.feedback;
  }
  return null;
}
