# Paridade com os mapeamentos da origem

Referências fornecidas em 16/10/2026:

- [Mapeamento dos dados Firebase](mapeamento-firebase-origem-2026-10-16.md)
- [Mapeamento de rotas e telas](mapeamento-rotas-origem-2026-10-16.md)
- [Regras de negócio](regras-negocio-origem-2026-10-16.md)

Esses arquivos descrevem a referência funcional. Seus links relativos apontam para o projeto React/Firebase. O objetivo é preservar os dados e os fluxos; esta base Flutter ainda não está em paridade completa e as telas novas ainda não foram feitas. Alterar a persistência para Supabase não autoriza perder campos, vínculos ou histórico.

## Estrutura física do Supabase existente

O diagnóstico recebido confirmou `public.nucleos(cod varchar PRIMARY KEY, sigla, nome, coordenador, ativo, created_at, updated_at)`. O banco também contém outros módulos com modelos diferentes dos do Firebase.

A correção aplicável a este projeto é **`202610160002_existing_registry.sql`**, independente e alternativa ao bootstrap de base nova. Ela reutiliza os códigos textuais dos núcleos e não altera a estrutura, policies, grants ou triggers do cadastro compartilhado. Não modifica os módulos de usuários, notas, consultas e outros existentes. Veja [schema-supabase-existente.md](schema-supabase-existente.md).

O bootstrap `202610160001_online_core.sql` agora verifica conflitos antes de qualquer DDL, dentro de transação. Não deve ser usado neste projeto. A adaptação foi testada localmente e sua execução hospedada foi confirmada pelo usuário. O banco pertence ao Cláudia; a integração adicional está descrita em [integracao-claudia.md](integracao-claudia.md).

## Correspondência dos dados

Os nomes abaixo descrevem o modelo relacional do bootstrap. A adaptação ao banco já existente está documentada em `schema-supabase-existente.md` e preserva `nucleos.cod` em texto.

| Firebase | Domínio/SQL planejado | Situação |
| --- | --- | --- |
| Auth UID → `users/{uid}` | `Identity`, `Profile`, `profiles.id` → `auth.users.id` | Autenticação separada de perfil; não promover perfil a partir de metadados editáveis |
| `users.name`, `email`, `role` | `Profile.name`, `email`, `role` | Nome/papel no perfil; email da conta Auth |
| `users.nucleos[]` | `Profile.nucleoIds`, `user_nucleos` | Relação explícita; sem conceder todos os núcleos por padrão |
| `users.mediumId`, `photoURL`, datas | `Profile.mediumId`, `photoUrl`, `createdAt`, `updatedAt` | Representação e leitura preparadas; vínculo/foto/datas incluídos no schema de adaptação. API de edição de perfil ainda pendente |
| `nucleos/{id}` | `Nucleo`, `nucleos` | Código/sigla/nome e datas compartilhados; descrição na extensão do módulo |
| `mediums/{id}` | `Medium`, `mediums` | Nome, grau, fita, ativo, motivo/data/autor da inativação, datas de criação/atualização |
| `mediums.nucleos[]` | `Medium.nucleoIds`, `medium_nucleos` | Relação com múltiplos núcleos |
| `mediums.guides[]` | `Guide`, `guides` | Guia pertence ao médium; falange referenciada por ID estável |
| `mediums.isPresent` | `attendance` por sessão | Presença compartilhada no servidor; há diferença de escopo frente ao booleano global da origem |
| `mediums.isAvailable/currentConsultation` | Derivados de presença e consulta em andamento | Não armazenar três estados contraditórios; futura tela recebe a projeção equivalente |
| `config` local/IndexedDB | `WorkSession`, `work_sessions` | Falange, duração, limite, dirigente e bloqueio persistidos online |
| `consultations/{data}/{id}` | `Consultation`, `consultations` | Consulta associada à sessão e núcleo; datas preservadas |
| `password`, `consultantName`, `mediumId`, `guideId` | `password`, `consultant_name`, `medium_id`, `guide_id` | Abertura e vínculos implementados no bootstrap |
| `mediumName`, `guideName` | `mediumName`, `guideName`; `medium_name`, `guide_name` | Snapshots históricos agora chegam ao domínio; não usar só o cadastro renomeado |
| `nucleoId`, `sessionDate` | `nucleoId`, `sessionId` e `WorkSession.day` | Legados sem núcleo/sessão não podem receber vínculos inventados |
| `phalanx`, `phalanxOfDay` | `phalanxId`, catálogo `phalanxes` | A importação terá de reconciliar os dois campos e preservar o valor original quando divergirem |
| `dirigentId`, `dirigentName` | `dirigentId`, `dirigentName` | ID preservado e snapshot do nome gravado pela adaptação; ambos chegam ao domínio |
| `classification`, `limitExceeded` | `isExtra`, getter `classification`; `is_extra` | Getter devolve `normal` ou `extra`; importador ainda não implementado |
| `limitExceededBy`, `limitOverrideReason` | `exceededBy`, `overrideReason`; `exceeded_by`, `override_reason` | Mantém quantidade e justificativa |
| `startTime`, `endTime` | `startedAt`, `endedAt`; `started_at`, `ended_at` | Datas opcionais quando ainda não iniciou/encerrou |
| `durationMinutes` | `serviceMinutes`; `service_minutes` | Duração efetiva. `duration_minutes` no bootstrap é a duração **prevista**, outro conceito |
| `status`, `rating`, `feedback` | Mesmos conceitos no domínio e SQL | Mantém estados e ausência de avaliação distinta de nota zero administrativa |
| `queuePosition`, `queuedAt` | `queuePosition`, `queuedAt` | Timestamp de espera gravado na adaptação; posição opcional representada no domínio. Ordem atual é por `created_at,id` |
| `createdAt`, `updatedAt`, `isTest` | `createdAt`, `updatedAt`, `isTest` | Datas e indicador chegam ao domínio |
| `reports/{pushId}` | Relatório diário próprio | Ainda pendente; não misturar com snapshot geral |
| `reports/general_snapshots/{núcleo|global}/{data}` | Snapshot geral próprio | Ainda pendente; manter sua regra específica sobre testes |
| `mediumStats/{id}` | Estatísticas por médium/guia | Ainda pendente, incluindo vínculo `Profile.mediumId` |
| Firestore `errorLogs` | Contrato de observabilidade a definir | Ainda pendente; não misturar com dados operacionais |

### Identificadores e importação

IDs Firebase como `0001` não são UUIDs. O ID de consulta é único dentro de uma partição de data, e o ID do guia pertence ao cadastro de um médium. Uma importação precisa de mapas estáveis, com as chaves de origem completas:

- Perfil: UID Firebase → conta Auth Supabase explicitamente associada.
- Consulta: data + ID de consulta → ID de destino.
- Guia: ID do médium + ID do guia → ID de destino.
- Núcleo e médium: ID original → ID de destino, preservando a referência original.

Não gerar UUIDs novos a cada tentativa de importação. Não juntar registros por nome ou deduzir núcleo ausente. As credenciais Auth não estão nos perfis RTDB; migrá-las exige procedimento próprio. Nenhuma importação foi implementada ou executada nesta etapa.

## Contrato das rotas

`lib/app/routing/route_catalog.dart` registra os 15 caminhos do mapa, requisitos de autenticação/núcleo, permissões do guard observado, itens do menu e destinos pós-login. É um contrato testado; não são telas prontas nem rotas fictícias registradas no GoRouter. O shell ainda registra apenas `/`.

Os testes preservam detalhes do comportamento original:

- `/consultation` não aparece no menu, embora seja acessível no fluxo de presença.
- `/feedback`, `/profile`, `/admin` e `/nucleos` dispensam seleção de núcleo no guard de navegação.
- No início, o guard de núcleo vem antes do redirecionamento de tablet para feedback.
- Login normal de `user` segue para `/`; o botão de continuação segue para `/consultation-room`.
- O menu compara papéis exatos; o RoleGuard usa níveis e permite `medium` em rotas operacionais por equivalência com `cambono`. Estatísticas individuais exigem `medium` exato.
- A rota desconhecida permanece pública para o futuro 404.

**Ponto ainda aberto:** o bootstrap Supabase atual é mais restritivo que o RoleGuard React para o perfil `medium`; ele não recebe acesso operacional. Registrar a regra de navegação de origem não altera RLS nem concede acesso no banco. Antes de ligar as telas, a matriz efetiva de autorização precisa ser alinhada de forma explícita. Não há autorização por plataforma.

## Critério de conclusão da paridade

Para cada tela do mapa: mesmo destino, campos, ações, mensagens e encadeamento; persistência efetiva identificada; testes dos perfis e núcleos; e diferenças registradas sem declarar a migração completa prematuramente. O mapa de rotas não documenta cores, dimensões ou o desenho exato de cada tela; a reprodução visual também dependerá dos componentes/assets de origem na etapa de UI.
