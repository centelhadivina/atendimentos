import 'package:flutter/material.dart';

import '../data/catalog_store.dart';

typedef Record = Map<String, Object?>;

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.store});
  final CatalogStore store;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  List<Record> nucleos = [], mediums = [], sessions = [];
  String? selectedSession;
  Map<String, List<String>> memberships = {};
  List<Record> attendance = [];
  bool busy = true;

  @override
  void initState() {
    super.initState();
    run(() async {});
  }

  Future<void> run(Future<void> Function() operation) async {
    setState(() => busy = true);
    try {
      await operation();
      final n = await widget.store.nucleos();
      final m = await widget.store.mediums();
      final s = await widget.store.sessions();
      final links = <String, List<String>>{};
      for (final medium in m) {
        links[medium['id'] as String] = await widget.store.memberships(
          medium['id'] as String,
        );
      }
      final a = selectedSession == null
          ? <Record>[]
          : await widget.store.attendance(selectedSession!);
      if (mounted) {
        setState(() {
          nucleos = n;
          mediums = m;
          sessions = s;
          attendance = a;
          memberships = links;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editNucleo([Record? row]) async {
    final values = await fields(
      'Núcleo',
      {
        'Nome': row?['name'] as String? ?? '',
        'Descrição': row?['description'] as String? ?? '',
      },
      optional: {'Descrição'},
    );
    if (values != null) {
      await run(() async {
        await widget.store.saveNucleo(
          id: row?['id'] as String?,
          name: values['Nome']!,
          description: values['Descrição']!,
        );
      });
    }
  }

  Future<void> editMedium([Record? row]) async {
    final links = row == null
        ? <String>[]
        : await widget.store.memberships(row['id'] as String);
    if (!mounted) return;
    final name = TextEditingController(text: row?['name'] as String?);
    final degree = TextEditingController(
      text: row?['degree'] as String? ?? 'Verde',
    );
    final reason = TextEditingController(
      text: row?['inactive_reason'] as String?,
    );
    var ribbon = row?['ribbon'] as String? ?? 'green';
    var active = row?['active'] != 0;
    final form = GlobalKey<FormState>();
    final accepted = await showSettledDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Médium'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nome'),
                      validator: requiredText,
                    ),
                    TextFormField(
                      controller: degree,
                      decoration: const InputDecoration(
                        labelText: 'Grau (Dirigente, Verde, Amarela…)',
                      ),
                      validator: requiredText,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: ribbon,
                      decoration: const InputDecoration(labelText: 'Fita'),
                      items: ribbons.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => ribbon = v!,
                    ),
                    const SizedBox(height: 16),
                    const Text('Núcleos — sem seleção: todos os núcleos'),
                    for (final n in nucleos)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(n['name'] as String),
                        value: links.contains(n['id']),
                        onChanged: (v) => update(() {
                          if (v!) {
                            links.add(n['id'] as String);
                          } else {
                            links.remove(n['id']);
                          }
                        }),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Ativo'),
                      value: active,
                      onChanged: (v) => update(() => active = v),
                    ),
                    if (!active)
                      TextFormField(
                        controller: reason,
                        decoration: const InputDecoration(
                          labelText: 'Motivo da inativação',
                        ),
                        validator: requiredText,
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
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await run(() async {
        await widget.store.saveMedium(
          id: row?['id'] as String?,
          name: name.text,
          degree: degree.text,
          ribbon: ribbon,
          nucleoIds: links,
          active: active,
          inactiveReason: reason.text,
        );
      });
    }
    name.dispose();
    degree.dispose();
    reason.dispose();
  }

  Future<void> showGuides(Record medium) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GuidePage(store: widget.store, medium: medium),
      ),
    );
    if (mounted) await run(() async {});
  }

  Future<void> editSession([Record? row]) async {
    if (nucleos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre um núcleo primeiro.')),
      );
      return;
    }
    var nucleo = row?['nucleo_id'] as String? ?? nucleos.first['id'] as String;
    var phalanx = row?['phalanx'] as String? ?? phalanxes.first;
    var dirigent = row?['dirigent_id'] as String? ?? '';
    final duration = TextEditingController(text: '${row?['duration'] ?? 20}');
    final limit = TextEditingController(
      text: '${row?['consultation_limit'] ?? 10}',
    );
    final form = GlobalKey<FormState>();
    final accepted = await showSettledDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Configuração • ${sessionDay(DateTime.now())}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: nucleo,
                    decoration: const InputDecoration(labelText: 'Núcleo'),
                    items: nucleos
                        .map(
                          (n) => DropdownMenuItem(
                            value: n['id'] as String,
                            child: Text(n['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: row == null ? (v) => nucleo = v! : null,
                  ),
                  TextFormField(
                    initialValue: phalanx,
                    enabled: row?['locked_at'] == null,
                    decoration: const InputDecoration(
                      labelText: 'Falange do dia',
                      helperText: 'Use a mesma falange cadastrada nos guias.',
                    ),
                    validator: requiredText,
                    onChanged: (v) => phalanx = v,
                  ),
                  if (row?['locked_at'] != null)
                    const Text('Falange travada após o primeiro atendimento.'),
                  TextFormField(
                    controller: duration,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duração (minutos)',
                    ),
                    validator: positiveNumber,
                  ),
                  TextFormField(
                    controller: limit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Limite por médium (inclui fila)',
                    ),
                    validator: positiveNumber,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: dirigent,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dirigente opcional',
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Nenhum')),
                      for (final m in mediums.where(
                        (m) =>
                            (m['degree'] == 'Dirigente' && m['active'] == 1) ||
                            m['id'] == dirigent,
                      ))
                        DropdownMenuItem(
                          value: m['id'] as String,
                          child: Text(m['name'] as String),
                        ),
                    ],
                    onChanged: (v) => dirigent = v!,
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
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await run(() async {
        selectedSession = await widget.store.saveSession(
          nucleoId: nucleo,
          phalanx: phalanx,
          duration: int.parse(duration.text),
          limit: int.parse(limit.text),
          dirigentId: dirigent.isEmpty ? null : dirigent,
        );
      });
    }
    duration.dispose();
    limit.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Cadastros e configuração diária'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Núcleos'),
            Tab(text: 'Médiuns e guias'),
            Tab(text: 'Dia e presença'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    FilledButton(
                      onPressed: busy ? null : editNucleo,
                      child: const Text('Novo núcleo'),
                    ),
                    for (final n in nucleos)
                      Card(
                        child: ListTile(
                          title: Text(n['name'] as String),
                          subtitle: Text(n['description'] as String),
                          trailing: const Icon(Icons.edit),
                          onTap: busy ? null : () => editNucleo(n),
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    FilledButton(
                      onPressed: busy ? null : editMedium,
                      child: const Text('Novo médium'),
                    ),
                    for (final m in mediums)
                      Card(
                        child: ListTile(
                          title: Text(
                            '${m['name']}${m['active'] == 0 ? ' • Inativo' : ''}',
                          ),
                          subtitle: Text(
                            '${m['degree']} • ${ribbons[m['ribbon']]}${m['active'] == 0 ? '\n${m['inactive_reason']}' : ''}',
                          ),
                          onTap: busy ? null : () => editMedium(m),
                          trailing: TextButton(
                            onPressed: busy ? null : () => showGuides(m),
                            child: const Text('Guias'),
                          ),
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text(
                      'O dia de trabalho muda às 03h no horário local. Configure cada núcleo e marque os médiuns presentes.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy ? null : editSession,
                      child: const Text('Configurar hoje'),
                    ),
                    for (final s in sessions)
                      Card(
                        child: ListTile(
                          selected: selectedSession == s['id'],
                          title: Text(
                            '${nucleos.where((n) => n['id'] == s['nucleo_id']).map((n) => n['name']).firstOrNull ?? ''} • ${s['day']}',
                          ),
                          subtitle: Text(
                            '${s['phalanx']} • ${s['duration']} min • limite ${s['consultation_limit']}',
                          ),
                          onTap: busy
                              ? null
                              : () {
                                  selectedSession = s['id'] as String;
                                  run(() async {});
                                },
                          trailing: s['day'] == sessionDay(DateTime.now())
                              ? IconButton(
                                  tooltip: 'Editar configuração',
                                  onPressed: busy ? null : () => editSession(s),
                                  icon: const Icon(Icons.edit),
                                )
                              : null,
                        ),
                      ),
                    if (selectedSession != null) ...[
                      const SizedBox(height: 16),
                      const Text('Presença da sessão selecionada'),
                      for (final m in mediums.where(
                        (m) =>
                            m['active'] == 1 &&
                            (memberships[m['id']]!.isEmpty ||
                                memberships[m['id']]!.contains(
                                  sessions.firstWhere(
                                    (s) => s['id'] == selectedSession,
                                  )['nucleo_id'],
                                )),
                      ))
                        SwitchListTile(
                          title: Text(m['name'] as String),
                          value: attendance.any(
                            (a) =>
                                a['medium_id'] == m['id'] && a['present'] == 1,
                          ),
                          onChanged:
                              busy ||
                                  sessions.firstWhere(
                                        (s) => s['id'] == selectedSession,
                                      )['day'] !=
                                      sessionDay(DateTime.now())
                              ? null
                              : (v) => run(
                                  () => widget.store.setPresence(
                                    selectedSession!,
                                    m['id'] as String,
                                    v,
                                  ),
                                ),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<Map<String, String>?> fields(
    String title,
    Map<String, String> initial, {
    Set<String> optional = const {},
  }) async => editFields(context, title, initial, optional: optional);
}

String? requiredText(String? value) =>
    value == null || value.trim().isEmpty ? 'Campo obrigatório' : null;
String? positiveNumber(String? value) => (int.tryParse(value ?? '') ?? 0) <= 0
    ? 'Informe um inteiro positivo'
    : null;

Future<Map<String, String>?> editFields(
  BuildContext context,
  String title,
  Map<String, String> initial, {
  Set<String> optional = const {},
}) async {
  final controllers = initial.map(
    (k, v) => MapEntry(k, TextEditingController(text: v)),
  );
  final form = GlobalKey<FormState>();
  final accepted = await showSettledDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in controllers.entries)
                  TextFormField(
                    controller: e.value,
                    decoration: InputDecoration(labelText: e.key),
                    validator: optional.contains(e.key) ? null : requiredText,
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
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  final result = accepted == true
      ? controllers.map((k, v) => MapEntry(k, v.text))
      : null;
  for (final c in controllers.values) {
    c.dispose();
  }
  return result;
}

class GuidePage extends StatefulWidget {
  const GuidePage({super.key, required this.store, required this.medium});
  final CatalogStore store;
  final Record medium;
  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  List<Record> guides = [];
  bool busy = true;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final rows = await widget.store.guides(widget.medium['id'] as String);
    if (mounted) {
      setState(() {
        guides = rows;
        busy = false;
      });
    }
  }

  Future<void> edit([Record? row]) async {
    final values = await editFields(context, 'Guia', {
      'Nome': row?['name'] as String? ?? '',
      'Falange': row?['phalanx'] as String? ?? phalanxes.first,
    });
    if (values == null) return;
    if (mounted) setState(() => busy = true);
    try {
      await widget.store.saveGuide(
        id: row?['id'] as String?,
        mediumId: widget.medium['id'] as String,
        name: values['Nome']!,
        phalanx: values['Falange']!,
      );
      await reload();
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Guias • ${widget.medium['name']}')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Use a mesma grafia da falange na configuração diária.'),
        if (busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: busy || widget.medium['active'] == 0 ? null : edit,
          child: const Text('Novo guia'),
        ),
        for (final g in guides)
          ListTile(
            title: Text(g['name'] as String),
            subtitle: Text(g['phalanx'] as String),
            trailing: const Icon(Icons.edit),
            onTap: busy || widget.medium['active'] == 0 ? null : () => edit(g),
          ),
      ],
    ),
  );
}

/// Mantém os controladores vivos até o fim da animação de saída.
Future<T?> showSettledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}
