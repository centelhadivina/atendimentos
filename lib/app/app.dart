import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'routing/route_catalog.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: AppRoute.home.path,
        builder: (_, _) => const Scaffold(
          body: Center(
            child: Text(
              'Centelha Consultas\nInterface em preparação.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class CentelhaOnlineApp extends ConsumerWidget {
  const CentelhaOnlineApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Centelha Consultas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xff6750a4),
      useMaterial3: true,
    ),
    routerConfig: ref.watch(routerProvider),
  );
}
