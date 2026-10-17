import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_sources.dart';

class SupabaseCatalogDataSource implements CatalogDataSource {
  const SupabaseCatalogDataSource(this.client);
  final SupabaseClient client;
  static const mediumSelection = '*, guides(*), medium_nucleos(nucleo_id)';
  @override
  Future<List<Json>> nucleos() async =>
      List<Json>.from(await client.rpc('list_consultation_nucleos'));
  @override
  Future<Json> saveNucleo(Json input) async => Map<String, dynamic>.from(
    await client.rpc('save_nucleo', params: {'p_data': input}),
  );
  @override
  Future<List<Json>> phalanxes() =>
      client.from('phalanxes').select().order('position');
  @override
  Future<List<Json>> mediums(bool includeInactive) async {
    final query = client.from('mediums').select(mediumSelection);
    return await (includeInactive ? query : query.eq('active', true)).order(
      'name',
    );
  }

  Future<Json> _medium(String id) =>
      client.from('mediums').select(mediumSelection).eq('id', id).single();
  @override
  Future<Json> saveMedium(Json input) async {
    final row = Map<String, dynamic>.from(
      await client.rpc('save_medium', params: {'p_data': input}),
    );
    return _medium(row['id'] as String);
  }

  @override
  Future<Json> setMediumActive(String id, bool active, String? reason) async {
    await client.rpc(
      'set_medium_active',
      params: {'p_id': id, 'p_active': active, 'p_reason': reason},
    );
    return _medium(id);
  }
}

class SupabaseSessionDataSource implements SessionDataSource {
  const SupabaseSessionDataSource(this.client);
  final SupabaseClient client;
  @override
  Future<Json?> current(String nucleoId) async {
    final data = await client.rpc(
      'current_work_session',
      params: {'p_nucleo_id': nucleoId},
    );
    return data == null ? null : Map<String, dynamic>.from(data);
  }

  @override
  Future<Json> configure(Json input) async => Map<String, dynamic>.from(
    await client.rpc('configure_session', params: {'p_data': input}),
  );
  @override
  Future<List<Json>> attendance(String sessionId) => client
      .from('attendance')
      .select()
      .eq('session_id', sessionId)
      .order('medium_id');
  @override
  Future<Json> setPresence(
    String sessionId,
    String mediumId,
    bool present,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
      'set_presence',
      params: {
        'p_session_id': sessionId,
        'p_medium_id': mediumId,
        'p_present': present,
      },
    ),
  );
}

class SupabaseConsultationDataSource implements ConsultationDataSource {
  const SupabaseConsultationDataSource(this.client);
  final SupabaseClient client;
  @override
  Future<List<Json>> list(String sessionId) => client
      .from('consultations')
      .select()
      .eq('session_id', sessionId)
      .order('created_at')
      .order('id');
  @override
  Stream<List<Json>> watch(String sessionId) => Stream<List<Json>>.multi((
    controller,
  ) {
    // Reconsulta autoritativa: remove também registros que deixaram de ser
    // visíveis pela RLS (ex.: feedback concluído por outro dispositivo).
    var cancelled = false;
    var loading = false;
    Future<void> refresh() async {
      if (loading || cancelled) return;
      loading = true;
      try {
        final rows = await list(sessionId);
        if (!cancelled) controller.add(rows);
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
      } finally {
        loading = false;
      }
    }

    final timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
    controller.onCancel = () {
      cancelled = true;
      timer.cancel();
    };
    unawaited(refresh());
  });
  @override
  Future<String> suggestPassword(String sessionId, String password) async =>
      await client.rpc(
        'suggest_password',
        params: {'p_session_id': sessionId, 'p_password': password},
      ) as String;
  @override
  Future<Json> open(Json input) async => Map<String, dynamic>.from(
    await client.rpc('open_consultation', params: {'p_data': input}),
  );
  @override
  Future<Json> start(String id) async => Map<String, dynamic>.from(
    await client.rpc('start_consultation', params: {'p_id': id}),
  );
  @override
  Future<Json> transfer(String id, String mediumId, String guideId) async =>
      Map<String, dynamic>.from(
        await client.rpc(
          'transfer_consultation',
          params: {'p_id': id, 'p_medium_id': mediumId, 'p_guide_id': guideId},
        ),
      );
  @override
  Future<Json> finish(String id, int rating, String comment) async =>
      Map<String, dynamic>.from(
        await client.rpc(
          'finish_consultation',
          params: {'p_id': id, 'p_rating': rating, 'p_feedback': comment},
        ),
      );
  @override
  Future<Json> cancel(String id) async => Map<String, dynamic>.from(
    await client.rpc('cancel_consultation', params: {'p_id': id}),
  );
  @override
  Future<List<Json>> findInProgress(String nucleoId, String query) async =>
      List<Json>.from(
        await client.rpc(
          'find_feedback_consultations',
          params: {'p_nucleo_id': nucleoId, 'p_query': query},
        ),
      );
}

class SupabaseAuthDataSource implements AuthDataSource {
  const SupabaseAuthDataSource(this.client);
  final SupabaseClient client;
  Json? _identity(User? user) =>
      user == null ? null : {'id': user.id, 'email': user.email};
  @override
  Json? get currentIdentity => _identity(client.auth.currentUser);
  @override
  Stream<Json?> watchIdentity() =>
      client.auth.onAuthStateChange.map((e) => _identity(e.session?.user));
  @override
  Future<Json> signIn(String email, String password) async => _identity(
    (await client.auth.signInWithPassword(
      email: email,
      password: password,
    )).user,
  )!;
  @override
  Future<Json?> signUp(String name, String email, String password) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'name': name},
    );
    return response.session == null ? null : _identity(response.user);
  }

  @override
  Future<void> signOut() => client.auth.signOut(scope: SignOutScope.local);
  @override
  Future<Json> quickSignIn(String nucleoId, String role) async {
    final response = await client.functions.invoke(
      'consultation-quick-access',
      body: {'nucleo_id': nucleoId, 'role': role},
    );
    final data = response.data;
    if (data is! Map ||
        data['refresh_token'] is! String ||
        (data['refresh_token'] as String).isEmpty) {
      throw const FormatException('Resposta de autenticação inválida.');
    }
    final result = await client.auth.setSession(
      data['refresh_token'] as String,
    );
    return _identity(result.user)!;
  }

  @override
  Future<Json> profile() async {
    if (client.auth.currentUser == null) throw AuthSessionMissingException();
    return Map<String, dynamic>.from(
      await client.rpc('my_consultation_profile'),
    );
  }
}
