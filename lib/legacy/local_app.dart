import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/consultation_store.dart';
import '../data/catalog_store.dart';
import '../presentation/catalog_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final factory = Platform.isWindows || Platform.isLinux || Platform.isMacOS
        ? databaseFactoryFfi
        : mobile.databaseFactory;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final store = await ConsultationStore.open(
      factory,
      p.join(dir.path, 'centelha.db'),
    );
    runApp(CentelhaApp(store: store));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'Não foi possível abrir os dados locais.\n$error',
            ),
          ),
        ),
      ),
    );
  }
}

class CentelhaApp extends StatelessWidget {
  const CentelhaApp({super.key, required this.store});
  final ConsultationStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Centelha • Consultas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6750a4)),
      scaffoldBackgroundColor: const Color(0xfff8f7fb),
    ),
    home: ConsultationPage(store: store),
  );
}

class ConsultationPage extends StatefulWidget {
  const ConsultationPage({super.key, required this.store});
  final ConsultationStore store;
  @override
  State<ConsultationPage> createState() => _ConsultationPageState();
}

class _ConsultationPageState extends State<ConsultationPage> {
  List<Map<String, Object?>> records = [];
  int pending = 0;
  List<Map<String, Object?>> sessions = [], nucleos = [];
  String? sessionId;
  bool legacy = false;
  bool busy = false;
  String filter = 'in_progress';
  Timer? timer;
  @override
  void initState() {
    super.initState();
    unawaited(action(reload));
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    final rows = await widget.store.all();
    final count = await widget.store.pendingCount();
    final daily = await widget.store.catalog.sessions();
    final centers = await widget.store.catalog.nucleos();
    if (mounted) {
      setState(() {
        records = rows;
        pending = count;
        sessions = daily;
        nucleos = centers;
        sessionId ??=
            daily
                    .where((s) => s['day'] == sessionDay(DateTime.now()))
                    .firstOrNull?['id']
                as String?;
      });
    }
  }

  Future<void> action(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      await reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> settings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CatalogPage(store: widget.store.catalog),
      ),
    );
    if (mounted) await action(() async {});
  }

  Future<void> create() async {
    final selected = sessionId;
    if (selected == null) return;
    final session = sessions.firstWhere((s) => s['id'] == selected);
    final attendance = await widget.store.catalog.attendance(selected);
    final allMediums = await widget.store.catalog.mediums();
    final eligible = <Map<String, Object?>>[];
    final guides = <String, List<Map<String, Object?>>>{};
    for (final m in allMediums) {
      if (m['active'] != 1 ||
          !attendance.any(
            (a) => a['medium_id'] == m['id'] && a['present'] == 1,
          )) {
        continue;
      }
      final id = m['id'] as String;
      final links = await widget.store.catalog.memberships(id);
      if (links.isNotEmpty && !links.contains(session['nucleo_id'])) continue;
      guides[id] = (await widget.store.catalog.guides(id))
          .where((g) => g['phalanx'] == session['phalanx'])
          .toList();
      if (guides[id]!.isNotEmpty) eligible.add(m);
    }
    if (!mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Marque a presença de um médium com guia da falange do dia em Cadastros e configuração.',
          ),
        ),
      );
      return;
    }
    var mediumId = eligible.first['id'] as String;
    var guideId = guides[mediumId]!.first['id'] as String;
    final password = TextEditingController(), name = TextEditingController();
    final form = GlobalKey<FormState>();
    final accepted = await showSettledDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Adicionar à fila'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: password,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Senha (1 a 4 dígitos)',
                      ),
                      validator: (v) =>
                          RegExp(r'^[0-9]{1,4}$').hasMatch(v?.trim() ?? '')
                          ? null
                          : 'Informe de 1 a 4 dígitos',
                    ),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Consulente',
                      ),
                      validator: requiredText,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: mediumId,
                      decoration: const InputDecoration(
                        labelText: 'Médium presente',
                      ),
                      items: eligible
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['id'] as String,
                              child: Text(m['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(() {
                        mediumId = v!;
                        guideId = guides[mediumId]!.first['id'] as String;
                      }),
                    ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(mediumId),
                      initialValue: guideId,
                      decoration: const InputDecoration(
                        labelText: 'Guia da falange do dia',
                      ),
                      items: guides[mediumId]!
                          .map(
                            (g) => DropdownMenuItem(
                              value: g['id'] as String,
                              child: Text(g['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => guideId = v!,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Salvar na fila'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await action(
        () => widget.store.create(
          password.text,
          name.text,
          mediumId,
          sessionId: selected,
          guideId: guideId,
        ),
      );
    }
    password.dispose();
    name.dispose();
  }

  Future<void> feedback(Map<String, Object?> row) async {
    var rating = 0;
    final comment = TextEditingController();
    final accepted = await showSettledDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Feedback • senha ${row['password']}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contingência pelo cambono'),
                const SizedBox(height: 16),
                Text('${row['consultant']} • ${row['medium']}'),
                const SizedBox(height: 16),
                Wrap(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        tooltip: 'Nota $i',
                        onPressed: () => update(() => rating = i),
                        icon: Icon(
                          i <= rating ? Icons.star : Icons.star_border,
                          color: Colors.amber.shade800,
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: comment,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Comentário (opcional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: rating == 0
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Salvar e encerrar'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await action(
        () => widget.store.finish(row['id'] as String, rating, comment.text),
      );
    }
    comment.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoped = records
        .where(
          (r) => legacy
              ? r['session_id'] == null
              : sessionId != null && r['session_id'] == sessionId,
        )
        .toList();
    final visible = scoped.where((r) => r['status'] == filter).toList();
    final selected = sessions.where((s) => s['id'] == sessionId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centelha • Consultas'),
        actions: [
          IconButton(
            tooltip: 'Cadastros e configuração',
            onPressed: busy ? null : settings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Cambono | Versão inicial'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            busy || legacy || selected?['day'] != sessionDay(DateTime.now())
            ? null
            : create,
        icon: const Icon(Icons.add),
        label: const Text('Nova consulta'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
            children: [
              Text(
                'Sala de atendimento',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Organize a fila e acompanhe as consultas.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: busy ? null : settings,
                icon: const Icon(Icons.settings),
                label: const Text('Cadastros e configuração diária'),
              ),
              if (sessions.isEmpty)
                const Text(
                  'Cadastre núcleos, médiuns e guias; depois configure o dia e marque as presenças.',
                ),
              if (sessions.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey(sessionId),
                  initialValue: sessionId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Núcleo e sessão',
                  ),
                  items: sessions
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(
                            '${nucleos.where((n) => n['id'] == s['nucleo_id']).firstOrNull?['name'] ?? ''} • ${s['day']} • ${s['phalanx']}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          sessionId = v;
                          legacy = false;
                        }),
                ),
              if (records.any((r) => r['session_id'] == null))
                SwitchListTile(
                  title: const Text(
                    'Consultar registros anteriores à migração',
                  ),
                  value: legacy,
                  onChanged: busy ? null : (v) => setState(() => legacy = v),
                ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.storage_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Dados neste dispositivo • $pending alterações pendentes\nNuvem e tablet ainda não conectados.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final tab in [
                    ('queue', 'Fila'),
                    ('in_progress', 'Em atendimento'),
                    ('completed', 'Encerradas'),
                  ])
                    ChoiceChip(
                      label: Text(
                        '${tab.$2} (${scoped.where((r) => r['status'] == tab.$1).length})',
                      ),
                      selected: filter == tab.$1,
                      onSelected: (_) => setState(() => filter = tab.$1),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (busy) const LinearProgressIndicator(),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: Text('Nenhuma consulta nesta etapa.')),
                ),
              for (final row in visible)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Senha ${row['password']} • ${row['consultant']}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text('Médium: ${row['medium']}'),
                        if (row['guide_name'] != null)
                          Text('Guia: ${row['guide_name']}'),
                        if (row['duration'] != null)
                          Text('Duração prevista: ${row['duration']} min'),
                        if (row['started_at'] != null)
                          Text(
                            'Tempo desde o início: ${DateTime.parse((row['ended_at'] ?? DateTime.now().toUtc().toIso8601String()) as String).difference(DateTime.parse(row['started_at'] as String)).inMinutes} min',
                          ),
                        if (filter == 'completed')
                          Text(
                            'Avaliação: ${row['rating']}/5\n${row['feedback'] ?? ''}',
                          ),
                        const SizedBox(height: 12),
                        if (filter == 'queue')
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => action(
                                    () =>
                                        widget.store.start(row['id'] as String),
                                  ),
                            child: const Text('Iniciar atendimento'),
                          ),
                        if (filter == 'in_progress')
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => feedback(row),
                            icon: const Icon(Icons.rate_review_outlined),
                            label: const Text(
                              'Feedback pelo cambono e encerrar',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
