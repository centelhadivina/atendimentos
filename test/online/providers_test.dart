import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:centelha_consultas/app/app.dart';
import 'package:centelha_consultas/application/providers.dart';
import 'package:centelha_consultas/application/commands.dart';
import 'package:centelha_consultas/data/remote/data_sources.dart';
import 'package:centelha_consultas/domain/entities.dart';
import 'package:centelha_consultas/domain/failure.dart';

class FakeCatalogSource implements CatalogDataSource {
  int reads = 0;
  bool fail = false;
  @override
  Future<List<Json>> nucleos() async {
    reads++;
    return [
      {'id': 'n', 'name': 'Núcleo', 'description': ''},
    ];
  }

  @override
  Future<Json> saveNucleo(Json input) async {
    if (fail) throw const AppFailure(FailureKind.forbidden, 'Sem permissão');
    return {...input, 'id': 'n'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Riverpod injeta datasource por contrato e devolve domínio sem SDK',
    () async {
      final source = FakeCatalogSource();
      final container = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          catalogDataSourceProvider.overrideWithValue(source),
          authIdentityProvider.overrideWith(
            (ref) => Stream.value(const Identity('u', 'email@example.com')),
          ),
        ],
      );
      final listener = container.listen(nucleosProvider, (_, _) {});
      addTearDown(listener.close);
      expect(
        (await container.read(nucleosProvider.future)).single.name,
        'Núcleo',
      );
      expect(source.reads, 1);
      await container
          .read(catalogCommandsProvider.notifier)
          .saveNucleo(name: 'Novo');
      expect(container.read(catalogCommandsProvider).hasError, false);
    },
  );
  test('Comando preserva falha para chamador e estado AsyncError', () async {
    final source = FakeCatalogSource()..fail = true;
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [catalogDataSourceProvider.overrideWithValue(source)],
    );
    await expectLater(
      container.read(catalogCommandsProvider.notifier).saveNucleo(name: 'Novo'),
      throwsA(isA<AppFailure>()),
    );
    expect(container.read(catalogCommandsProvider).hasError, true);
  });
  test('Leitura sem autenticação não consulta datasource', () async {
    final source = FakeCatalogSource();
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        catalogDataSourceProvider.overrideWithValue(source),
        authIdentityProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    final listener = container.listen(nucleosProvider, (_, _) {});
    addTearDown(listener.close);
    await expectLater(
      container.read(nucleosProvider.future),
      throwsA(isA<AppFailure>()),
    );
    expect(source.reads, 0);
  });
  testWidgets('Bootstrap GoRouter é independente do protótipo SQLite', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CentelhaOnlineApp()));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(
      find.text('Centelha Consultas\nInterface em preparação.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
