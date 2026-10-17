# Centelha Consultas

Um aplicativo Flutter para **Android, Windows e Web**, sem restrição de funções por plataforma. **Clean Architecture, SOLID, Riverpod e GoRouter.** Primeiro o fluxo online com Supabase; depois persistência offline e sincronização com SQLite.

## Etapa atual: domínio e dados online

Implementados contratos, entidades, casos de uso, datasources Supabase, repositórios e providers/comandos Riverpod para autenticação, núcleos, médiuns/guias, configuração diária, presença, fila e feedback. Operações de negócio usam RPCs transacionais com autorização por perfil/núcleo e RLS.

As **novas telas ainda não foram implementadas**. O entrypoint padrão inicializa Supabase e abre somente o shell GoRouter. O banco é compartilhado com o sistema **Cláudia**. O usuário confirmou sucesso da migração `202610160002_existing_registry.sql` em 16/10/2026. A API reconhece `phalanxes` e recusa sua leitura anônima, conforme esperado. Não execute novamente a instalação nem o bootstrap `202610160001` neste projeto. Ainda é necessário validar o fluxo com uma conta autenticada e suas concessões de núcleo.

- [Paridade de dados e rotas com os novos mapas](docs/paridade-firebase-flutter.md)
- [Arquitetura e cobertura desta etapa](docs/arquitetura-dados.md)
- [Regras de negócio anexadas, revisão 16/10/2026](docs/regras-negocio-origem-2026-10-16.md)
- [Migração SQL e preparação do Supabase](supabase/README.md)
- [Adaptação ao cadastro compartilhado existente](docs/schema-supabase-existente.md)
- [Integração relacional com o Cláudia](docs/integracao-claudia.md)
- [Acessos rápidos e master admin do Consultas](docs/acessos-consultas.md)

## Configuração e execução

O arquivo local `config/supabase.json` está configurado com a URL e a chave **pública** fornecidas e é ignorado pelo Git. Em outra máquina, copie `config/supabase.example.json` para `config/supabase.json` e preencha seus valores. Nunca use `service_role` ou chave secreta no app.

```sh
flutter pub get
flutter run -d chrome --dart-define-from-file=config/supabase.json
flutter run -d windows --dart-define-from-file=config/supabase.json
# Android: selecione o emulador/dispositivo em flutter devices.
flutter run -d ID_DO_ANDROID --dart-define-from-file=config/supabase.json
```

Windows exige Visual Studio com Desktop development with C++. Android usa a permissão INTERNET também no build de release. Configuração, entidades e operações não dependem de `dart:io`, SQLite ou plataforma no fluxo online.

## Organização

```text
lib/domain/             Entidades, contratos e casos de uso (Dart puro)
lib/data/remote/        Contratos técnicos, mappers, datasources Supabase
lib/data/repositories/ Implementações dos contratos de domínio
lib/application/       Composição e estado Riverpod
lib/app/               Shell e GoRouter
lib/main.dart          Bootstrap online
supabase/migrations/   Schema, RLS e RPCs atômicas
supabase/tests/        Testes SQL no PostgreSQL embarcado
```

Os padrões novos são **30 minutos / 3 consultas** e o limite condicional com justificativa descrito no documento anexado. As regras 20/10 e o bloqueio geral de limite do protótipo SQLite anterior não orientam a implementação nova.

## Verificar

```sh
flutter analyze
flutter test
flutter build web --dart-define-from-file=config/supabase.json
python3 tool/check_supabase.py
```

A suíte usa transporte HTTP simulado para os testes Dart do SDK e PostgreSQL embarcado para verificar SQL/RLS. Consulte `supabase/README.md` para executar os testes SQL e para as verificações que ainda exigem o Supabase hospedado.

## Protótipo SQLite anterior

Preservado como referência, com seus dados e outbox locais. Não é acionado pelo fluxo online e não sincroniza com Supabase:

```sh
flutter run -t lib/main_legacy.dart -d windows
```

Esse protótipo tem regras antigas e não é a implementação offline definitiva. A etapa futura de SQLite deverá atender também Web e reutilizar os contratos novos. O [mapa anterior](docs/regras-migracao.md) descreve apenas esse protótipo e foi superado pelas regras anexadas para o fluxo novo.

## Próximos incrementos

1. Aplicar a migração 003 de acessos, provisionar/reaproveitar as contas existentes e publicar a função de acesso rápido conforme `docs/acessos-consultas.md`; validar o fluxo autenticado.
2. Completar os casos de uso pendentes: relatórios, estatísticas, fechamento diário e administração de usuários/falanges.
3. Implementar telas com Riverpod e GoRouter, inclusive feedback no mesmo aplicativo.
4. Implementar offline com SQLite, sincronização, confirmação, conflitos e contingência; se a coleta de feedback falhar em outro dispositivo, o operador poderá registrar e encerrar no próprio app.

Não foi feita importação Firebase nem limpeza de dados locais. A migração remota foi executada pelo usuário. Nenhum instalador Windows ou APK validado foi entregue nesta etapa.
