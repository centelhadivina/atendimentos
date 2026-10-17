# Adaptação ao Supabase existente

Diagnóstico fornecido pelo usuário em 16/10/2026. O banco pertence ao sistema **Cláudia** e é compartilhado com seus módulos. Não é uma instalação vazia do Centelha Consultas.

## Conflito identificado

`public.nucleos` possui chave primária `cod varchar`, `sigla varchar NOT NULL UNIQUE`, `nome varchar NOT NULL`, `coordenador`, `ativo`, `created_at` e `updated_at`. Há um trigger `atualizar_nucleos_updated_at`, leitura pública e escrita autenticada configuradas pelo sistema existente.

Não há `public.nucleos.id`, `name` ou `description`. Por isso, além do erro de relação existente, apenas trocar `CREATE TABLE` por `CREATE TABLE IF NOT EXISTS` não resolveria a migração: os tipos e referências também seriam incompatíveis.

O diagnóstico também mostrou `usuarios`, `usuarios_sistema`, `consultas`, `nota_consultas`, cadastros, cursos, cerimônias, grupos e outros módulos. Não são os mesmos modelos do Firebase enviados nos mapeamentos:

- `consultas` tem `numero_consulta`, vínculo com `usuarios` e datas; não possui estados e fila do fluxo Firebase.
- `nota_consultas` aceita notas de 0 a 10; feedback do app de consultas é 1 a 5.
- `usuarios_sistema` tem IDs próprios e níveis numéricos. Não há evidência de que correspondam aos UIDs Auth e papéis do novo aplicativo.
- `dia_sessao` é um cadastro de dias/responsáveis, não a sessão operacional diária com falange, duração e limite.

## Correção aplicada

**Arquivo executado pelo usuário, com sucesso confirmado em 16/10/2026:** `supabase/migrations/202610160002_existing_registry.sql`.

É um arquivo **independente e alternativo** ao bootstrap `supabase/bootstrap/202610160001_online_core.sql`. O bootstrap foi retirado da pasta `migrations` para que não seja aplicado junto da adaptação. Não executar os dois arquivos.

A adaptação:

1. Confere os tipos e a PK do cadastro existente antes de criar objetos.
2. Reutiliza `nucleos.cod` em texto nos vínculos de usuário, médium, sessão e consulta, preservando códigos com zeros à esquerda.
3. Não altera estrutura, policies, grants, índices ou triggers de `public.nucleos`. Cria a extensão `consultation_nucleo_details` para a descrição do módulo.
4. Cria `profiles`, `user_nucleos`, `phalanxes`, `mediums`, `medium_nucleos`, `guides`, `work_sessions`, `attendance` e `consultations`, com proteção própria do módulo.
5. Não escreve em `usuarios`, `usuarios_sistema`, `dados_mediunicos`, `dia_sessao`, `consultas`, `nota_consultas` ou demais cadastros existentes. Não importa automaticamente os dados dessas tabelas.
6. Inclui vínculo opcional de perfil com médium, foto/datas, snapshot do nome do dirigente e `queued_at` na nova estrutura.
7. Usa transação para que erro reverta a execução inteira. Reexecução sobre objetos já criados é interrompida antes de mudanças, sem apagar dados.

`list_consultation_nucleos()` adapta `cod/sigla/nome` para `id/code/abbreviation/name` e aplica as concessões do módulo. O datasource usa essa RPC. As permissões anteriores de acesso direto à tabela compartilhada continuam como estavam; o módulo não as substitui.

Para criar um núcleo no cadastro compartilhado, código e sigla são obrigatórios no banco existente. O contrato aceita `code` e `abbreviation`; o servidor os exige na criação. Editar um núcleo já existente preserva código e sigla se não forem enviados. Alterar o código é recusado. Editar nome/sigla é uma alteração explícita no cadastro compartilhado, visível aos outros módulos. Nenhum núcleo existente é renomeado automaticamente pela migração.

Novas FKs preservam a relação com os núcleos: um núcleo referenciado por sessões/histórico não poderá ser excluído enquanto houver vínculos. A migração não converte códigos para UUID.

## Perfis e autenticação

Perfis novos são vinculados a `auth.users.id`, recebem `user` e não obtêm núcleos automaticamente. Não há conversão de `usuarios_sistema.nivel_permissao` em privilégios do aplicativo novo. A promoção inicial de administrador continua sendo explícita pelo administrador do projeto.

## Testes

A suíte `online_core.mjs`, com `CENTELHA_EXISTING_REGISTRY=1`, aplica o arquivo de adaptação a uma fixture com os tipos, PK, sigla única, políticas e trigger do cadastro compartilhado. Compara os registros e metadados compartilhados antes/depois e verifica regras operacionais com códigos textuais. Há também registros sintéticos em `usuarios`, `consultas` e `nota_consultas` (incluindo nota 9,5), que devem permanecer intactos.

A fixture reproduz as partes relevantes do diagnóstico; não é uma cópia integral do banco remoto. O usuário confirmou sucesso da execução hospedada. A sonda reconheceu `phalanxes` e recebeu HTTP 401 / `42501` para leitura anônima, como esperado pelos grants. A validação autenticada das RPCs e dos vínculos com o Cláudia ainda precisa ocorrer.
