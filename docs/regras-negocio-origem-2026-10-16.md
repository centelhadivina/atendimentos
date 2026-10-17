# Regras de negócio do Centelha Consultas

**Revisado em:** 16/10/2026  
**Base:** comportamento implementado no código deste repositório.

Este documento reúne as regras observáveis da aplicação, incluindo validações da interface, transições do atendimento, cálculos e persistência. Quando uma regra aparece apenas como aviso ou configuração, isso é indicado: não deve ser interpretada como bloqueio efetivo. Os pontos em que as camadas divergem estão reunidos em [Diferenças e pontos de atenção](#diferenças-e-pontos-de-atenção).

## 1. Conceitos e dados

- **Núcleo:** unidade escolhida para operar o sistema. A seleção é guardada no navegador e é exigida para as rotas operacionais, exceto feedback, perfil e administração.
- **Médium:** cadastro com nome, grau, fita, guias, presença, disponibilidade e associação a um ou mais núcleos. Um médium pode ter grau “Médium” ou “Dirigente” e uma fita amarela, verde, azul, anil, roxa, colorida ou branca.
- **Guia:** pertence ao cadastro de um médium e a uma falange.
- **Consulta:** associa senha, consulente, médium e guia; pode também registrar núcleo, falange e dirigente do dia, classificação, horários, avaliação e comentário.
- **Consulta de teste:** é identificada pelo indicador `isTest` ou por “teste” como palavra no nome do consulente. É excluída de vários totais e estatísticas, mas não de todos; ver a seção de relatórios.

Fontes: [modelos de consulta](../src/domain/consultation/Consultation.ts), [tipos de usuário e configuração](../src/types/index.ts), [cadastro de médium](../src/models/Medium.ts).

## 2. Acesso, perfis e núcleo

Os perfis definidos são `admin`, `user`, `tablet`, `medium` e `cambono`. Um cadastro novo recebe o perfil `user`. O perfil `tablet` é encaminhado ao feedback depois do login; o perfil `medium` tem uma tela de estatísticas individuais. As rotas operacionais de configuração, presença, consulta e sala exigem autenticação, seleção de núcleo e perfil autorizado pela interface. Cadastro de médiuns, histórico, relatórios e estatísticas globais são apresentados como funcionalidades administrativas.

O núcleo selecionado é persistido em `localStorage`. Ao carregar consultas, a aplicação mantém as do núcleo selecionado e também as consultas antigas sem `nucleoId`; estas últimas são tratadas como pertencentes ao núcleo atual em alguns filtros.

Fontes: [login e criação de usuário](../src/cubits/AuthCubit.ts), [rotas e proteção da interface](../src/App.tsx), [seleção de núcleo](../src/context/NucleoContext.tsx), [consulta e filtragem por núcleo](../src/context/ConsultationContext.tsx).

## 3. Cadastro e disponibilidade de médiuns

- Para salvar um médium pela interface, nome, grau, pelo menos um núcleo e guias completos são obrigatórios. Nomes duplicados (ignorando maiúsculas/minúsculas e espaços nas extremidades) são recusados.
- A interface não permite mais de um guia da mesma falange por médium e exige guia para cada uma das sete falanges fixas (`PHALANXES`).
- O cadastro permite editar informações e guias. A desativação exige motivo, grava a justificativa e data, e marca o médium como ausente e indisponível. A reativação limpa os metadados de inativação.
- A listagem padrão do datasource omite registros com `isActive === false`; registros antigos sem esse campo continuam ativos. A ação “remover” do fluxo normal também é uma inativação lógica, não uma exclusão física.
- Marcar presença torna o médium disponível; desmarcar presença o torna indisponível. Ao limpar presenças ou encerrar o relatório diário, todos os presentes passam a ausentes e indisponíveis.
- A lista de médiuns disponíveis exige simultaneamente `isPresent` e `isAvailable`.

Fontes: [formulário de cadastro](../src/components/MediumRegistration.tsx), [persistência de médiuns](../src/datasources/firebase/MediumDataSource.ts), [regras de presença e disponibilidade](../src/context/ConsultationContext.tsx).

## 4. Configuração do trabalho

- Valores iniciais: primeira falange da lista fixa (“Exus e Pombogiras”), duração de 30 minutos e limite de 3 consultas por médium.
- A interface recusa duração menor que 30 minutos e limite menor que 3. Não há limite superior definido nessa validação.
- É possível escolher falange do dia, dirigente, editar a lista de falanges e remover ou renomear falanges, respeitando as validações da interface.
- A primeira consulta iniciada grava `dayLockedAt`. A falange permanece travada até depois das 03:00 do dia seguinte; a configuração desbloqueia a falange no fechamento do relatório diário.
- Ao criar, iniciar da fila ou trocar o guia de uma consulta, o guia precisa pertencer à falange do dia atual.
- Duração configurada gera alertas quando faltam até 5 minutos e quando o tempo se esgota. O alerta de fim informa que é apenas um aviso: a consulta continua aberta até ser encerrada.

Fontes: [configuração e valores iniciais](../src/context/ConfigurationContext.tsx), [tela de configuração](../src/components/ConsultationSetup.tsx), [validação de falange e bloqueio diário](../src/context/ConsultationContext.tsx), [alertas de duração](../src/components/ConsultationRoom.tsx).

## 5. Senhas, abertura de consultas e limite por médium

- Para iniciar uma consulta, a interface exige senha, nome do consulente, médium e guia. A senha digitada aceita até quatro algarismos; ao persistir, zeros à esquerda são normalizados e uma letra final é permitida.
- Se já existir consulta no mesmo núcleo com a mesma senha-base, o fluxo propõe a senha-base ou a próxima variação livre de `a` a `z` (por exemplo, `123a`). Se todas as 26 variações estiverem ocupadas, não permite continuar. A verificação inclui consultas existentes independentemente do status.
- Se o médium estiver disponível, o atendimento começa imediatamente. Se estiver indisponível, a consulta entra na fila `waiting`.
- Para médium indisponível, a contagem usada no limite é: consultas concluídas hoje, sem consultas de teste, mais consultas atualmente na fila daquele médium. Se o total já for igual ou superior ao limite configurado, a interface exige confirmação para excedê-lo.
- Para confirmar o excesso, o motivo deve conter pelo menos cinco palavras. O registro marca a consulta como extra e guarda motivo e quantidade excedida; o relatório diário acumula os eventos de excedente da sessão.
- A validação do limite por médium não é aplicada pelo mesmo fluxo quando o médium está disponível. Ela é, portanto, uma regra condicional da interface, não um bloqueio geral na criação.

Fontes: [formulário de nova consulta](../src/components/NewConsultationForm.tsx), [criação e metadados da consulta](../src/context/ConsultationContext.tsx), [confirmação de excedente](../src/components/LimitExceededDialog.tsx).

## 6. Fila de espera e estados

Estados definidos: `waiting`, `queue`, `in_progress`, `completed` e `cancelled`. As transições permitidas pelo state machine são:

| Estado atual | Próximos estados |
|---|---|
| `waiting` ou `queue` | `in_progress`, `cancelled` |
| `in_progress` | `completed`, `cancelled` |
| `completed` ou `cancelled` | nenhum |

O mesmo estado é permitido. No fluxo atual de criação, a fila usa `waiting`; `queue` existe no enum e no state machine, mas não é o estado usado pela tela da fila.

- A ordem da fila é por data de criação, da mais antiga para a mais nova, separada por médium.
- A chamada da próxima consulta é sugerida para médiuns presentes e disponíveis; a interface reavalia a cada cinco segundos. A chamada pode ser adiada por cinco minutos.
- Ao iniciar uma consulta da fila, o estado passa a `in_progress` e o médium fica indisponível.
- É possível trocar o médium de uma consulta ainda em espera. O novo guia deve ser da falange do dia; se o médium de destino estiver disponível, a consulta inicia imediatamente.
- A troca de médium não é permitida para uma consulta que já saiu de `waiting`.

Fontes: [state machine](../src/domain/consultation/ConsultationStateMachine.ts), [detecção e chamada da fila](../src/components/CallNextDialog.tsx), [fila e troca de médium](../src/components/WaitingQueue.tsx), [operações de fila](../src/context/ConsultationContext.tsx).

## 7. Conclusão, cancelamento e feedback

- O feedback pode localizar a consulta por senha ou por parte do nome do consulente, mas só permite selecionar consultas em andamento.
- A tela de feedback exige uma avaliação de 1 a 5; comentário é opcional. O envio conclui a consulta, grava a avaliação e encerra o médium como disponível somente se ainda estiver presente.
- O tempo de atendimento armazenado é arredondado para minutos e limitado a zero como mínimo.
- Conclusão em lote usa avaliação `0`, que representa ausência de avaliação enviada pelo consulente.
- Cancelar pela senha procura consulta que não esteja concluída nem cancelada. Em fluxo normal, a consulta é removida do banco; se estiver em andamento há mais de duas horas, é marcada como cancelada para recuperação, em vez de removida.
- Cancelar todas as consultas em andamento libera os médiuns e remove as consultas canceladas no fluxo normal. Consultas em espera não fazem parte dessa operação.

Fontes: [feedback](../src/components/Feedback.tsx), [conclusão de consulta](../src/application/consultation/ConsultationUseCases.ts), [cancelamento e operações em lote](../src/context/ConsultationContext.tsx), [regra de recuperação após duas horas](../src/utils/consultationRecovery.ts).

## 8. Fechamento do dia e relatórios

Há dois fluxos diferentes de encerramento:

1. **Finalizar trabalho na sala:** a interface bloqueia a operação enquanto houver consultas não-testes em andamento ou em espera. Ao prosseguir, salva um relatório diário; após salvar, limpa presenças, zera os excedentes temporários e desbloqueia a falange.
2. **Encerrar dia em configuração/administração:** conclui as consultas em andamento com avaliação `0` e limpa as presenças. Esse fluxo não chama a geração do relatório diário e não remove consultas em espera.

O relatório diário:

- Conta consultas concluídas iniciadas hoje e exclui consultas de teste.
- Calcula o tempo total com consultas de hoje que tenham início e fim; o cálculo inclui as que têm fim mas não são `completed` (por exemplo, canceladas).
- Agrupa por médium e guia, calcula médias usando avaliações maiores que zero, registra dirigente/falange e distribui por fita apenas nas categorias dirigente, amarela e verde.
- Registra os excedentes de limite acumulados desde o último fechamento com relatório.

O snapshot geral é diferente: é salvo ao concluir consultas e conta as concluídas hoje por núcleo, mas não exclui consultas de teste. Relatórios e histórico filtram testes e exibem consultas concluídas ou canceladas. Estatísticas individuais também excluem testes e calculam médias sobre consultas concluídas com avaliação maior que zero.

Fontes: [fechamento e relatório diário](../src/context/ConsultationContext.tsx), [snapshot geral](../src/application/reports/ReportService.ts), [filtros de relatórios](../src/pages/Reports.tsx), [estatísticas individuais](../src/pages/MediumStats.tsx).

## 9. Persistência e operação offline

- As consultas são organizadas no Realtime Database por data (`consultations/AAAA-MM-DD`) e usam a data de criação para determinar a partição.
- O carregamento padrão busca o dia atual; histórico e relatórios podem consultar intervalos ou meses.
- A consulta começa a ser persistida online na abertura ou entrada na fila. Para operações offline há armazenamento local e operações pendentes de sincronização.
- A configuração da falange e dos limites é persistida em armazenamento local do navegador/IndexedDB; a lista de falanges também usa `localStorage`. Logo, a configuração não é apresentada como configuração central compartilhada pelo banco.
- Ao detectar presença ou consultas pendentes de dias anteriores, o app apresenta aviso. A limpeza correspondente reinicia presença e configurações (duração e limite para 30 e 3) e remove consultas pendentes antigas.

Fontes: [datasource de consultas](../src/datasources/firebase/ConsultationDataSource.ts), [contexto de configuração](../src/context/ConfigurationContext.tsx), [recuperação e limpeza](../src/context/ConsultationContext.tsx), [armazenamento offline](../src/utils/offlineStorage.ts).

## 10. Diferenças e pontos de atenção

Estes itens descrevem lacunas entre o comportamento esperado pelos nomes/comentários e o que está efetivamente ligado no código:

1. **Presença por núcleo:** o cadastro associa médiuns a núcleos, mas a tela de presença usa todos os médiuns, sem filtrar pela associação ao núcleo selecionado.
2. **Limite global de 150 consultas/dia:** o número e a validação aparecem no monitor de performance e em comentário das regras, mas não são chamados pelo fluxo de criação. A regra do Realtime Database só exige autenticação para escrita e não aplica esse limite.
3. **Duração máxima de uma hora:** a validação no encerramento registra aviso e ainda permite finalizar. A validação de uma hora em `firestore.rules` não corresponde ao datasource usado pela aplicação (Realtime Database), e esse arquivo não está referenciado em `firebase.json`.
4. **Controles de acesso:** os valores de perfil da aplicação são minúsculos (`admin`, `user` etc.), enquanto `firestore.rules` compara valores maiúsculos (`ADMIN`, `USER`). Além disso, `RoleGuard` compara níveis hierárquicos, não apenas igualdade com os perfis listados; perfis `medium` e `cambono` podem satisfazer rotas do mesmo nível (a página de estatísticas do médium ainda faz uma verificação adicional de perfil exato). Os guards de rota são controle de interface.
5. **Regras efetivas do Realtime Database:** `firebase.json` referencia `database.rules.json`, que permite leitura e escrita a qualquer usuário autenticado nos caminhos listados. As restrições de papel e limite descritas em `firestore.rules` não são as regras referenciadas por essa configuração.
6. **Teste e métricas:** consultas de teste são excluídas das estatísticas e do relatório diário, mas podem entrar no snapshot geral. Para comparar totais, deve-se considerar essa diferença.
7. **Encerramento sem relatório:** “Encerrar dia” na configuração conclui consultas ativas e limpa presença, mas não gera o relatório que o fluxo de finalização da sala gera; consultas em espera também não são tratadas como consultas em andamento nessa operação.
8. **Falanges editáveis:** a configuração permite editar a lista de falanges, mas o cadastro ainda valida a cobertura da lista fixa `PHALANXES`. Uma falange personalizada pode não ser suficiente para satisfazer essa validação.
9. **Validações auxiliares:** o limite de 10 atendimentos simultâneos está definido em um utilitário, mas não é chamado pelo fluxo de criação. O limite de 150 é um monitor/aviso e não deve ser entendido como bloqueio.

Fontes de conferência: [tela de presença](../src/components/MediumAttendance.tsx), [monitor e limites diários](../src/components/PerformanceMonitor.tsx), [validações de performance](../src/utils/performanceOptimizer.ts), [regras RTDB](../database.rules.json), [regras Firestore](../firestore.rules), [configuração Firebase](../firebase.json), [proteção de rotas](../src/components/RoleGuard.tsx), [validação de falanges no cadastro](../src/components/MediumRegistration.tsx).
