> Documento histórico do protótipo SQLite. Para a arquitetura online atual, consulte [arquitetura-dados.md](arquitetura-dados.md) e as [regras anexadas em 16/10/2026](regras-negocio-origem-2026-10-16.md).

# Mapa de regras e decisões da migração

Análise realizada em 16/10/2026 sobre o commit [`e65186a`](https://github.com/centelhadivina/consultas/tree/e65186aa8466c43ff15e396b87a2bdbf837c773b). O sistema contém caminhos paralelos em componentes, contexto e cubits; o comportamento nem sempre é uniforme. Este mapa distingue o código original das decisões adotadas no Flutter.

## Cadastros

| Regra observada | Fonte original | Flutter nesta etapa |
| --- | --- | --- |
| Núcleo possui ID, nome e descrição | [Nucleo.ts](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/models/Nucleo.ts) | Cadastro e edição persistentes |
| Médium possui nome, grau, fita, guias e vínculos com vários núcleos | [Medium.ts](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/models/Medium.ts) | UUIDs; relações médium–núcleo e médium–guia |
| Fitas: amarela, verde, azul, índigo, violeta, colorida, branca | [types/index.ts](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/types/index.ts) | Mesmos códigos; grau continua sendo texto, como no modelo original |
| Guia pertence ao médium e possui nome e falange | [types/index.ts](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/types/index.ts) | Cadastro/edição separados, com IDs estáveis |
| Médium sem vínculos é elegível em todos os núcleos | [MediumAttendance.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/components/MediumAttendance.tsx) | Mesmo comportamento; com vínculos, deve pertencer ao núcleo |
| Inativação exige motivo e permite reativação | [MediumRegistration.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/components/MediumRegistration.tsx) | Sem exclusão física; inativos não podem entrar em presença ou novas consultas |

Edições de médium e guia com fila ou atendimento pendente são bloqueadas para preservar a coerência. Consultas guardam também os nomes no momento do cadastro, preservando o histórico após renomear. As operações da outbox guardam a hora de cada alteração; campos de autoria e auditoria autenticada ficam para a integração futura.

## Configuração diária e presença

Fontes: [ConsultationSetup.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/components/ConsultationSetup.tsx), [ConsultationContext.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/context/ConsultationContext.tsx), [MediumAttendance.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/components/MediumAttendance.tsx).

- Configuração: falange do dia, duração em minutos, limite por médium e dirigente opcional. Origem usa padrão de 20 minutos e 10 consultas; Flutter usa os mesmos valores iniciais. Duração e limite devem ser inteiros positivos.
- Dirigente deve ter grau exatamente `Dirigente`. Flutter exige também médium ativo e elegível no núcleo; ele não precisa estar presente para ser escolhido na configuração.
- A falange trava no primeiro início efetivo de atendimento, em transação com a consulta e a outbox. Não é destravada ao encerrar a consulta.
- A duração não pode mudar enquanto houver atendimentos em andamento na sessão. O limite pode ser ajustado; reduzi-lo não remove consultas já cadastradas e impede novas entradas acima do limite. O início usa a duração vigente da sessão e a registra na consulta.
- Trocar falange antes do primeiro atendimento só é permitido se os guias da fila continuarem compatíveis.
- A presença agora pertence à sessão do núcleo e dia, em vez dos booleanos globais do médium. Uma sessão nova começa sem presença; mudar de núcleo não reaproveita presença de outro núcleo.
- A configuração original permite manter uma lista personalizada de falanges. Nesta etapa, há as sete falanges de referência no código e campos de texto para falanges de guia/dia, com correspondência exata após remover espaços externos. Um catálogo compartilhado de falanges com renomeação em cascata ainda não foi portado.

### Divergência de horário na origem

O bloqueio de falange em `ConsultationSetup`/`ConsultationContext` desbloqueia após 03h do dia seguinte, mas [offlineStorage.ts](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/utils/offlineStorage.ts) calcula sessão anterior até 06h e mistura esse cálculo com data UTC. Outros contadores usam dia civil.

**Decisão desta etapa:** uma sessão por núcleo e dia de trabalho, virando às **03h no horário local do dispositivo**; o intervalo antes das 03h pertence à data anterior. Não misturar os três critérios da origem. A sessão anterior fica preservada e pode ter seu feedback registrado, mas não aceita novas entradas nem novos inícios. A autoridade de horário/fuso no servidor deverá ser definida na sincronização.

## Atendimento

Fontes: [Consultation.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/components/Consultation.tsx), [ConsultationContext.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/context/ConsultationContext.tsx), [WaitingQueue.tsx](https://github.com/centelhadivina/consultas/blob/e65186aa8466c43ff15e396b87a2bdbf837c773b/src/components/WaitingQueue.tsx).

| Tema | Original | Flutter nesta etapa |
| --- | --- | --- |
| Senha | Entrada numérica de até quatro dígitos; busca ignora encerradas | 1–4 dígitos, preservando zeros; única na sessão inteira, inclusive encerradas |
| Guia | Validação da falange do dia no contexto | Valida existência, vínculo ao médium e falange ao cadastrar e iniciar |
| Presença e disponibilidade | Booleanos globais e `currentConsultation` | Presença por sessão; ocupação derivada das consultas, sem booleano duplicado |
| Exclusividade | Proteções distribuídas nos caminhos de início | Um atendimento por ID de médium em toda a base, inclusive entre núcleos |
| Estados | `waiting`, `queue`, `in_progress`, `completed` | Mantém fila única `queue → in_progress → completed` da base Flutter |
| Limite | Tela verifica encerradas + espera ao enfileirar médium ocupado; permite ultrapassar com motivo registrado | Bloqueio conservador: fila + andamento + encerradas na sessão por médium; sem exceção ainda |
| Ordem e remanejamento | Posição de fila, chamada do próximo, transferência entre médiuns | Início manual; transferência, chamada automática e posição formal pendentes |
| Mínimo de presença | Tela de presença exige três para avançar | Não imposto nesta etapa; um médium elegível e presente pode atender |
| Feedback | Tablet e outros caminhos de encerramento, incluindo administrativo com nota zero | Mantém nota 1–5 e comentário opcional no encerramento pelo cambono; reenvio não altera o primeiro feedback |
| Tempo | Duração configurável e indicadores de tempo | Exibe duração prevista e tempo decorrido; alertas ainda pendentes |

As diferenças acima são explícitas: esta entrega cobre cadastros e configuração diária e ainda não representa paridade completa do fluxo React.

## Persistência e migração

- SQLite versão 2 com chaves estrangeiras habilitadas. UUIDs identificam núcleos, médiuns, guias, sessões e operações.
- Migração v1 → v2 recria a tabela de consultas para remover unicidade global da senha. Preserva IDs, senha, nomes, estado, datas, nota e comentário. Não inventa núcleos, sessões ou vínculos por igualdade de nome.
- Consultas antigas permanecem acessíveis pelo seletor “Consultar registros anteriores à migração”. Mantêm início/feedback de contingência; novas consultas exigem os cadastros e a sessão atual. Para compatibilidade, atendimentos antigos também participam do bloqueio por nome quando não há ID.
- A migração preserva integralmente os payloads e IDs antigos da outbox e acrescenta `entity_type`/`entity_id`. Operações novas carregam o estado da entidade; médium inclui seus vínculos e presença usa sessão/médium. `consultation_id` permanece como coluna de compatibilidade na outbox, preenchida com o ID da entidade em operações novas; o futuro sincronizador deverá usar `entity_type` e `entity_id`.
- Cada alteração e sua operação são gravadas em uma única transação; falha na alteração não deixa operação órfã.
- Não há envio, confirmação, limpeza de outbox nem estratégia de conflitos implementados. O formato atual ainda precisará de revisão/versionamento para o protocolo remoto.

## Arquitetura de uso acordada

**Internet é o modo normal. Offline é contingência.** A base desta entrega ainda opera somente no dispositivo porque a sincronização não existe. A interface informa essa limitação e não simula conexão.

O destino é Windows para o cambono e Android para feedback. Se o tablet falhar, o cambono registra feedback e encerra no Windows. Supabase, autenticação, autorização por papel/núcleo, pareamento do tablet, importação Firebase, sincronização idempotente, resolução de conflitos, relatórios, backup e criptografia permanecem para os próximos incrementos. Nenhum dado foi publicado ou importado do sistema original.
