# Mapeamento dos dados do Firebase

**Revisado em:** 16/10/2026  
**Projeto configurado no app:** `consultas-centelha`  
**Realtime Database:** `consultas-centelha-default-rtdb`

Este documento descreve os caminhos (nós/tabelas) que o código consulta ou grava, seus campos principais, relações e regras configuradas. O Realtime Database é uma estrutura JSON em árvore, não um banco relacional com tabelas SQL.

## Visão geral

```text
Realtime Database
├── users/{userId}
├── mediums/{mediumId}
├── nucleos/{nucleoId}
├── consultations/{yyyy-MM-dd}/{consultationId}
├── reports/{reportId}              # relatório diário com ID push
├── reports/general_snapshots/{nucleoId|global}/{yyyy-MM-dd}
├── mediumStats/{mediumId}
└── config/                         # declarado nas regras; sem uso de persistência encontrado no app

Cloud Firestore
└── errorLogs/{autoId}

Firebase Authentication
└── usuários autenticáveis por email/senha (credencial separada do perfil em /users)
```

## Realtime Database

### `/users/{userId}` — perfis de usuário

O ID do nó é o UID do Firebase Authentication para usuários criados pelo fluxo de cadastro do app. O perfil do app é armazenado separadamente das credenciais.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `name` | string | Nome de exibição |
| `email` | string | Email do usuário |
| `role` | string | Perfil: `admin`, `user`, `tablet`, `medium` ou `cambono` |
| `nucleos` | string[] | IDs de núcleos associados ao usuário |
| `mediumId` | string, opcional | ID do médium vinculado a perfil `medium` |
| `photoURL` | string, opcional | URL da foto |
| `createdAt` | ISO string | Data de criação |
| `updatedAt` | ISO string | Data da última atualização |

IDs alternativos numéricos são gerados por `UserDataSource.create`; o cadastro pela autenticação usa UID via `createWithId`.

**Relações:** `nucleos[]` aponta para `/nucleos/{nucleoId}`; `mediumId` aponta para `/mediums/{mediumId}`.

Fonte: [UserDataSource](../src/datasources/firebase/UserDataSource.ts), [modelo User](../src/models/User.ts), [cadastro no AuthCubit](../src/cubits/AuthCubit.ts).

### `/mediums/{mediumId}` — médiuns, guias e disponibilidade

IDs novos são sequenciais em formato de quatro dígitos (`0001`, `0002`, ...). Os registros desativados permanecem no banco como soft delete.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `name` | string | Nome |
| `degree` | string | Grau (na interface: `Médium` ou `Dirigente`) |
| `ribbon` | string | Cor: `yellow`, `green`, `blue`, `indigo`, `purple`, `colorful` ou `white` |
| `guides` | array de objetos | Guias cadastrados (veja campos abaixo) |
| `isPresent` | boolean | Presença na sessão |
| `isAvailable` | boolean | Disponibilidade para iniciar consulta |
| `currentConsultation` | string ou null | ID da consulta ativa |
| `nucleos` | string[] | IDs dos núcleos onde trabalha |
| `isActive` | boolean | `false` indica médium inativo; ausente em registros antigos é tratado como ativo |
| `inactiveReason` | string, opcional | Motivo informado ao inativar |
| `inactivatedAt` | ISO string, opcional | Data da inativação |
| `inactivatedBy` | string, opcional | UID de quem inativou, se fornecido |
| `createdAt` | ISO string | Data de criação |
| `updatedAt` | ISO string | Data da última atualização |

Cada objeto em `guides[]` tem:

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string | Identificador do guia |
| `name` | string | Nome |
| `phalanx` | string | Falange do guia |

**Relações:** `nucleos[]` aponta para `/nucleos/{nucleoId}`; `currentConsultation` aponta para uma consulta sob `/consultations/{data}/{consultationId}`. Os guias são subdocumentos/objetos dentro do médium, não um nó de topo independente.

Fonte: [MediumDataSource](../src/datasources/firebase/MediumDataSource.ts), [modelo Medium](../src/models/Medium.ts), [tipo GuideType](../src/types/index.ts).

### `/nucleos/{nucleoId}` — unidades de operação

O datasource gera IDs numéricos sequenciais em novos cadastros.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `name` | string | Nome do núcleo |
| `description` | string | Descrição |
| `createdAt` | ISO string | Data de criação |
| `updatedAt` | ISO string | Data da última atualização |

Consultas e cadastros de médiuns referenciam esses registros por ID. A seleção ativa do navegador fica em `localStorage` (`centelha-selected-nucleo`), não é gravada como preferência remota do usuário pelo contexto de núcleo.

Fonte: [NucleoDataSource](../src/datasources/firebase/NucleoDataSource.ts), [modelo Nucleo](../src/models/Nucleo.ts), [NucleoContext](../src/context/NucleoContext.tsx).

### `/consultations/{yyyy-MM-dd}/{consultationId}` — atendimentos por data

O nó de data usa `createdAt` no momento da criação (`yyyy-MM-dd`). O identificador é sequencial dentro desse nó. Os valores de data/hora da consulta são persistidos como ISO strings.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `password` | string | Senha, podendo terminar em uma letra |
| `consultantName` | string | Nome do consulente |
| `isTest` | boolean, opcional | Marca teste; nome contendo “teste” também é considerado teste em alguns relatórios |
| `mediumId` | string | ID do médium |
| `mediumName` | string, opcional | Nome do médium no momento do atendimento |
| `guideId` | string | ID do guia dentro do cadastro do médium |
| `guideName` | string, opcional | Nome do guia guardado para histórico |
| `nucleoId` | string, opcional | Núcleo associado; ausente em registros legados |
| `sessionDate` | string, opcional | Data de sessão |
| `phalanx` | string, opcional | Campo de falange legado/alternativo |
| `phalanxOfDay` | string, opcional | Falange configurada para o dia |
| `dirigentId` | string, opcional | ID do dirigente do dia |
| `dirigentName` | string, opcional | Nome do dirigente no momento do atendimento |
| `classification` | `normal` ou `extra`, opcional | Classificação da consulta |
| `limitExceeded` | boolean, opcional | Indica excedente de limite |
| `limitExceededBy` | number, opcional | Quantidade acima do limite |
| `limitOverrideReason` | string, opcional | Justificativa do excedente |
| `startTime` | ISO string ou ausente | Início do atendimento; nulo não é persistido pelo mapper |
| `endTime` | ISO string ou ausente | Fim do atendimento |
| `durationMinutes` | number, opcional | Duração arredondada em minutos |
| `status` | string | `waiting`, `queue`, `in_progress`, `completed` ou `cancelled` |
| `rating` | number ou ausente | Avaliação; normalmente 1–5 ou 0 para conclusão administrativa |
| `feedback` | string ou ausente | Comentário do consulente |
| `queuePosition` | number, opcional | Posição em fila, se fornecida |
| `queuedAt` | data/hora, opcional | Momento em que entrou na fila, se fornecido |
| `createdAt` | ISO string | Data de criação |
| `updatedAt` | ISO string | Data da última atualização |

Os campos opcionais não são garantidos em todos os registros. O mapper omite `null` e `undefined` ao gravar; atualizações podem, portanto, deixar de limpar um valor remoto ao enviar `null`.

**Relações:** `mediumId` relaciona com `/mediums`; `guideId` identifica um dos guias do médium; `nucleoId` relaciona com `/nucleos`; `dirigentId` relaciona com `/mediums`.

Fonte: [ConsultationDataSource](../src/datasources/firebase/ConsultationDataSource.ts), [modelo Consultation](../src/domain/consultation/Consultation.ts), [mapper de persistência](../src/domain/consultation/ConsultationMapper.ts).

### `/reports/{reportId}` — relatórios diários

`reportId` é gerado com `push()` do Realtime Database. Esse nó armazena o relatório diário criado pelo fluxo “Finalizar trabalho” na sala.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `date` | `yyyy-MM-dd` | Dia do relatório |
| `totalConsultations` | number | Total de consultas concluídas computadas no relatório |
| `totalWorkTime` | number | Tempo total, em minutos |
| `limitOverrides` | array de objetos | Registros de excedente, com IDs/nomes, limite, contagens, quantidade excedida, justificativa e timestamp |
| `distributionByMedium` | array de objetos | Contagens e média por médium; inclui `guideStats` por guia |
| `distributionByRibbon` | objeto | Contagens para `yellow`, `green` e `dirigent` |
| `phalanxOfDay` | string | Falange do dia |
| `dirigentId` | string, opcional | ID do dirigente |
| `dirigentName` | string, opcional | Nome do dirigente |
| `createdAt` | ISO string | Momento em que o relatório foi gravado |

Detalhes de `distributionByMedium[]`: `mediumId`, `mediumName`, `consultations`, `averageRating` e `guideStats[]`. Cada item de guia tem `guideId`, `guideName`, `consultations` e `averageRating`.

### `/reports/general_snapshots/{nucleoId|global}/{yyyy-MM-dd}` — snapshots gerais

É sobrescrito por núcleo e data ao concluir consultas (não é criado com `push()`). Se não houver núcleo selecionado, a chave é `global`.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `date` | `yyyy-MM-dd` | Dia do snapshot |
| `phalanxOfDay` | string | Falange do dia |
| `totalConsultations` | number | Consultas concluídas computadas |
| `consultationsByMedium` | array | Itens com `mediumId`, `mediumName` e `consultations` |
| `mediumCount` | number | Quantidade de médiuns com consulta no snapshot |
| `totalWorkTime` | number | Tempo total em minutos |
| `nucleoId` | string, opcional | Núcleo do snapshot |
| `updatedAt` | ISO string | Momento da última gravação |

Fonte dos dois tipos de relatório: [ReportDataSource](../src/datasources/firebase/ReportDataSource.ts), [tipos DailyReport e GeneralReportSnapshot](../src/types/index.ts).

### `/mediumStats/{mediumId}` — estatísticas acumuladas por médium

Um nó por médium; a aplicação atualiza essas estatísticas ao montar o relatório diário. O reset de um médium zera os contadores, sem remover o nó.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `mediumId` | string | ID do médium |
| `mediumName` | string | Nome |
| `degree` | string | Grau |
| `totalConsultations` | number | Total acumulado |
| `averageRating` | number | Média de avaliação acumulada |
| `commandedSessions` | number | Total de sessões comandadas |
| `guideStats` | array de objetos | Estatísticas acumuladas por guia |
| `lastUpdated` | ISO string | Data da última atualização |

Cada item de `guideStats[]`: `guideId`, `guideName`, `totalConsultations` e `averageRating`.

Fonte: [MediumStatsDataSource](../src/datasources/firebase/MediumStatsDataSource.ts), [tipo MediumGlobalStats](../src/types/index.ts).

### `/config` — nó declarado, sem persistência remota localizada

`database.rules.json` declara permissões para o nó `config`, mas não foi encontrado código do app lendo ou escrevendo essa localização. A configuração operacional (`phalanxOfDay`, `consultationDuration`, `consultationLimit`, `dirigentId` e `dayLockedAt`) é guardada em `localStorage` e IndexedDB do navegador.

## Cloud Firestore

### `errorLogs/{autoId}` — erros do navegador

Os documentos são inseridos com ID automático pelo Firestore. O gerenciador também grava logs localmente como fallback.

| Campo | Tipo observado | Descrição |
|---|---|---|
| `id` | string | ID gerado pelo app e também gravado como campo no documento |
| `timestamp` | number | Época em milissegundos |
| `date` | string | Data ISO `yyyy-MM-dd` |
| `level` | string | `error`, `warn`, `info`, `runtime` ou `promise` |
| `message` | string | Mensagem do erro |
| `screen` | string | Rota/tela |
| `browser` | string | Navegador detectado |
| `userAgent` | string | User agent do navegador |
| `url` | string | Rota e query string atuais |
| `stack` | string, opcional | Stack trace |
| `source` | string, opcional | Origem capturada |
| `details` | objeto | Detalhes adicionais |
| `createdAt` | number | Época em milissegundos da gravação |

O código também cria armazenamento IndexedDB `errorLogs`; se este falhar, usa `localStorage` limitado aos 200 registros mais recentes.

Fonte: [errorLogManager](../src/utils/errorLogManager.ts).

## Firebase Authentication e relações

Firebase Authentication mantém credenciais de acesso (email/senha) e UID. O perfil da aplicação, com role e associações, é mantido em Realtime Database em `/users/{uid}`. Excluir o perfil de `/users` não equivale necessariamente a excluir a conta de autenticação.

```text
Auth UID ───────────────> users/{userId}
users.nucleos[] ────────> nucleos/{nucleoId}
users.mediumId ─────────> mediums/{mediumId}
mediums.nucleos[] ──────> nucleos/{nucleoId}
mediums.currentConsultation ─> consultations/{data}/{consultationId}
consultations.mediumId ─> mediums/{mediumId}
consultations.guideId ──> guides[] dentro de mediums/{mediumId}
consultations.nucleoId ─> nucleos/{nucleoId}
consultations.dirigentId -> mediums/{mediumId}
mediumStats/{mediumId} -> mediums/{mediumId}
```

## Regras de acesso configuradas

- [firebase.json](../firebase.json) referencia `database.rules.json` para deploy das regras do Realtime Database. O arquivo permite leitura e escrita em `mediums`, `consultations`, `users`, `nucleos`, `config` e `reports` se `auth != null`. Não contém regra para `mediumStats`; pela regra padrão do Realtime Database, caminhos sem permissão explícita ficam negados.
- [firestore.rules](../firestore.rules) descreve regras para coleções Firestore (`users`, `mediums`, `consultations`, `reports`, `mediumStats`, `nucleos` e `errorLogs`), mas não está referenciado no `firebase.json` atual. O uso identificado do Firestore no código é `errorLogs`.
- O formato de consultas descrito em `firestore.rules` (`consultations/{date}/items/{id}`) é distinto do caminho atualmente usado pelo app no Realtime Database (`consultations/{date}/{id}`).
- [storage.rules](../storage.rules) bloqueia leitura e escrita do Cloud Storage.
- O app usa regras configuradas pelo projeto Firebase no ambiente de execução; a configuração do repositório, sozinha, não confirma quais regras estão publicadas no Console.

Consulte [FIX_DATABASE_NOW.md](./FIX_DATABASE_NOW.md) para o procedimento de importação e validação de dados legado. Para as regras funcionais do app, veja [REGRAS_DE_NEGOCIO.md](./REGRAS_DE_NEGOCIO.md).
