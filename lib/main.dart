import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'application/providers.dart';
import 'core/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = SupabaseConfig.fromEnvironment()..validate();
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      authOptions: FlutterAuthClientOptions(
        persistSession: true,
        localStorage: SharedPreferencesLocalStorage(
          persistSessionKey: 'centelha-consultas-auth-v1',
        ),
      ),
      postgrestOptions: const PostgrestClientOptions(
        requestTimeout: Duration(seconds: 15),
      ),
    );
    runApp(
      ProviderScope(
        retry: retryRemoteProvider,
        overrides: [
          supabaseClientProvider.overrideWithValue(Supabase.instance.client),
        ],
        child: const CentelhaOnlineApp(),
      ),
    );
  } catch (_) {
    // A configuração e o bootstrap não devem expor chaves nem detalhes da sessão.
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Não foi possível inicializar o Centelha.\nConfira a configuração do Supabase e a conexão.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
