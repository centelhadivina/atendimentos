# Preparar o Supabase

## Estado atual

O usuário confirmou sucesso da migração em 16/10/2026. O banco é do sistema **Cláudia**. A API reconhece `phalanxes` e recusa leitura anônima (HTTP 401 / `42501`), conforme esperado. **Não execute novamente a instalação neste projeto.** O próximo passo é preparar conta/permissões e validar as operações autenticadas.

## Arquivo usado no projeto existente

Arquivo já aplicado pelo usuário:

**`migrations/202610160002_existing_registry.sql`**

Esse arquivo é independente e substitui o bootstrap `202610160001_online_core.sql` neste projeto. Não execute o bootstrap primeiro. A pasta `migrations` contém apenas a adaptação aplicável; o bootstrap de base vazia foi separado em `bootstrap/`.

O diagnóstico confirmou que `public.nucleos` já existe com `cod/sigla/nome`. A adaptação reutiliza o código textual e preserva a estrutura, policies, grants e triggers dessa tabela. Não altera os módulos `usuarios`, `usuarios_sistema`, `consultas`, `nota_consultas` etc. Veja [a adaptação detalhada](../docs/schema-supabase-existente.md).

Após executar no SQL Editor, confira:

```sql
select name, required_for_registration from public.phalanxes order by position;
select to_regclass('public.consultations');
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'work_sessions'
  and column_name = 'nucleo_id'; -- Deve ser text, não uuid.
```

Devem aparecer sete falanges e a tabela `public.consultations`. A execução é transacional; se houver um erro, não apague tabelas para tentar novamente. Reexecução após sucesso será interrompida para evitar sobrepor o módulo existente.

## Acessos do Consultas

O usuário definiu acessos separados do Cláudia: quatro contas rápidas cambono/tablet de CCU/CPO e `cinthiadutra@gmail.com` como master admin. Aplicar a migração adicional `202610160003_consultation_accounts.sql` e seguir [acessos-consultas.md](../docs/acessos-consultas.md) para provisionar/reaproveitar contas e publicar o backend do atalho.

A migração 003 só vincula emails aprovados e confirmados e não cria contas Auth. Contas do Cláudia não recebem acesso ao módulo automaticamente. Não promover outros usuários por níveis de `usuarios_sistema` nem unificar os perfis. A migração 003 e a função de acesso rápido ainda não foram aplicadas remotamente.

## Somente para outro projeto com base vazia

`bootstrap/202610160001_online_core.sql` é o bootstrap alternativo para uma base nova. Ele cria seu próprio cadastro de núcleos UUID e não pode ser aplicado a este banco compartilhado. Não executar essa alternativa junto com `202610160002_existing_registry.sql`.

## Diagnóstico e testes locais

`diagnostics/existing_schema.sql` é somente leitura e não consulta registros de pessoas. Ele já foi usado para identificar a estrutura deste projeto.

Os testes usam PGlite (PostgreSQL embarcado) em memória, sem Docker e sem acessar o Supabase remoto:

```sh
npm install --prefix /tmp/centelha-pg-validation @electric-sql/pglite@0.5.10
# Fluxo com o cadastro compartilhado deste projeto:
CENTELHA_EXISTING_REGISTRY=1 PGLITE_MODULE=/tmp/centelha-pg-validation/node_modules/@electric-sql/pglite/dist/index.js node supabase/tests/online_core.mjs
# Verificação do bootstrap alternativo:
PGLITE_MODULE=/tmp/centelha-pg-validation/node_modules/@electric-sql/pglite/dist/index.js node supabase/tests/online_core.mjs
# Interrupção sem alterações quando o bootstrap encontra tabela existente:
PGLITE_MODULE=/tmp/centelha-pg-validation/node_modules/@electric-sql/pglite/dist/index.js node supabase/tests/schema_safety.mjs
```

O Auth mínimo dos testes é uma fixture; o ambiente remoto usa `auth.uid()` e contas do Supabase. Ainda é necessário validar Auth hospedado e concorrência em duas conexões/dispositivos.

`python3 tool/check_supabase.py` é uma sonda somente de leitura. HTTP 200 no Auth confirma a conexão; erro de permissão anônima na relação protegida é esperado após a migração. A sonda não autentica usuário nem prova o fluxo de negócio completo.
