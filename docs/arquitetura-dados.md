# Arquitetura da base online

## Direção atual

Um aplicativo Flutter para Android, Windows e Web, sem funções vinculadas à plataforma. Clean Architecture, SOLID, Riverpod para composição/estado e GoRouter para rotas. Primeiro o fluxo online com Supabase; persistência offline e sincronização com SQLite vêm depois.

Os mapas posteriores de [dados e rotas](paridade-firebase-flutter.md) também são referência de paridade. O [diagnóstico Supabase](schema-supabase-existente.md) confirmou um cadastro compartilhado de núcleos com `cod/sigla/nome`; a adaptação aplicável é `202610160002_existing_registry.sql`, preservando esse schema.

O documento de regras entregue em 16/10/2026 está preservado em [regras-negocio-origem-2026-10-16.md](regras-negocio-origem-2026-10-16.md) e substitui as premissas anteriores do protótipo local. Os links relativos desse documento referem-se ao repositório React de origem.

## Dependências

```text
App / futuras telas (GoRouter)
         ↓
Aplicação (providers de leitura e comandos Riverpod)
         ↓
Domínio (entidades, validações, casos de uso, contratos dos repositórios)
         ↑ implementado por
Dados (repositórios remotos → contratos dos datasources → Supabase)
```

- `lib/domain`: Dart puro, independente de Flutter, Riverpod, JSON, Supabase e SQLite. Entidades imutáveis e contratos específicos para autenticação, catálogo, sessão e consulta.
- `lib/data/remote`: contratos técnicos, mapeamentos JSON e implementações Supabase. As RPCs concentram alterações transacionais. O SDK fica nesta camada e no bootstrap/composição.
- `lib/data/repositories`: implementa contratos do domínio, transforma respostas em entidades e converte falhas técnicas em `AppFailure`. Não converte erro de rede em sucesso ou lista vazia.
- `lib/application`: injeção de dependências e estado assíncrono com Riverpod. Casos de uso recebem interfaces. Providers podem ser substituídos por fakes sem inicializar o SDK. Comandos propagam falhas ao chamador e ao estado; a futura tela poderá preservar os dados digitados.
- `lib/app`: GoRouter e shell mínimo. Telas de login, cadastros e operação ainda não foram implementadas nesta arquitetura.
- `supabase/migrations`: schema, integridade, RLS e operações de negócio. Nenhuma função cliente usa chave administrativa.

A composição por providers substitui a `DataSourceFactory` estática do documento de origem. Adicionar a implementação SQLite posteriormente não exigirá introduzir SQL nas telas ou SDK no domínio. Não há fallback offline no fluxo online atual.

## Entregue neste incremento

| Área | Implementação |
| --- | --- |
| Autenticação | Login, cadastro com confirmação de e-mail, logout, identidade e perfil; novos usuários recebem `user` no servidor |
| Catálogos | Leitura e escrita de núcleos; leitura de falanges; agregado de médium com vínculos e guias; inativação/reativação |
| Configuração | Sessão atual, falange, dirigente, mínimos 30 minutos/3 consultas; presença por sessão |
| Consulta | Sugestão de senha, abertura imediata ou espera, excesso com justificativa, início da fila, transferência, feedback, cancelamento e busca para feedback |
| Estado | Providers de identidade, perfil, catálogos, sessão, presença e consultas; comandos assíncronos e invalidação das leituras |
| Navegação | GoRouter no shell; sem telas operacionais ou guards fictícios |

## Regras aplicadas

- Nome de médium único ignorando caixa e espaços externos; ao menos um núcleo; um guia por falange e cobertura das sete falanges obrigatórias. O cadastro agregado é gravado em uma transação. IDs de guia são preservados ao editar; guias referenciados pelo histórico não podem ser removidos.
- Grau usa os códigos `medium` e `dirigente`, correspondentes a “Médium” e “Dirigente”; fita usa os sete códigos do modelo de origem.
- Configuração começa em 30/3 e aceita valores maiores. Falange trava no primeiro início. Duração não muda durante atendimento em andamento.
- Senha normaliza zeros e uma letra final. `suggestPassword` consulta base e variações `a..z`; não reserva a senha. `open` confirma a senha informada e a unicidade é garantida no banco, inclusive em concorrência. Um conflito deve provocar nova sugestão e confirmação pela futura tela.
- Médium presente e livre inicia imediatamente; ocupado entra em `waiting`. A ocupação é derivada de consultas, sem booleano independente que possa ficar desatualizado. Índice parcial impede dois atendimentos simultâneos para o mesmo médium em qualquer núcleo.
- O limite é condicional ao médium ocupado: concluídas no dia civil em São Paulo sem testes, mais fila da sessão. Não inclui o atendimento em andamento. A partir do limite, exige cinco palavras de justificativa e grava `is_extra`, motivo e excedente. Quando livre, não aplica bloqueio geral por limite.
- Marcar ausente não encerra a consulta. Ao finalizar, o médium só estará elegível se continuar presente. Inativos não entram em novos atendimentos.
- `waiting`/`queue` podem iniciar ou cancelar; andamento pode concluir ou cancelar; estados terminais não reabrem. Reenvios de início, conclusão ou cancelamento preservam o primeiro resultado válido.
- Feedback exige 1–5; comentário opcional; duração armazenada arredondada e limitada a zero. Sem encerramento automático por tempo, bloqueio global de 150/dia ou máximo de uma hora.
- Consulta de teste é detectada pelo indicador ou pela palavra “teste” no nome; a contagem usada no limite exclui testes concluídos.
- Datas/timestamps são definidos pelo servidor. A sessão usa dia de trabalho com virada às 03h em `America/Sao_Paulo`; o contador de concluídas do limite usa dia civil, como descreve a regra anexada.

## Decisões explícitas em relação ao legado

1. Presença e configuração são compartilhadas por sessão/núcleo no servidor. Não reproduzimos presença global nem configuração isolada no navegador.
2. A associação ao núcleo é validada no servidor, corrigindo o filtro ausente descrito no item 10 do documento original.
3. Cancelamento preserva o registro com `cancelled`, inclusive antes de duas horas. Não copiamos a exclusão física do legado. Isso também mantém a senha ocupada na sessão e permite auditoria futura.
4. Edição/inativação de médium com consultas pendentes é bloqueada; deve-se encerrar, cancelar ou transferir primeiro.
5. Falanges têm IDs estáveis e as sete referências iniciais. Edição/remoção de falanges ainda não tem API de escrita neste incremento; o catálogo não pode ficar inconsistente com os guias.
6. Leitura de consultas é atualizada por polling autoritativo a cada cinco segundos. Isso também remove da lista de um tablet as consultas que deixaram de ser visíveis pela RLS após a conclusão em outro dispositivo. A publicação Realtime foi preparada, mas o fluxo de observação não depende dela nesta etapa.

## Autorização efetiva no servidor

RLS para leituras; clientes autenticados não têm escrita direta nas tabelas. As RPCs são `SECURITY DEFINER`, fixam `search_path`, validam perfil e núcleo e têm execução revogada para `anon`. A role da aplicação é lida da tabela protegida `profiles`, nunca dos metadados editáveis do usuário.

- `admin`: gerencia cadastros e opera em qualquer núcleo.
- `user`/`cambono`: operam apenas núcleos concedidos em `user_nucleos`.
- `tablet`: consulta atendimentos em andamento e envia feedback em núcleos concedidos; não cria, cancela ou configura consultas.
- `medium`: não ganha permissões operacionais; estatísticas individuais serão implementadas em incremento próprio.

Essas permissões correspondem ao papel da conta, em qualquer plataforma. Uma conta `tablet` não significa uma restrição do Android.

A migração adicional 003 prepara os emails autorizados do Consultas e o master `cinthiadutra@gmail.com`, exigindo email confirmado e sem aproveitar os níveis de `usuarios_sistema`. Ainda precisa ser aplicada remotamente. As contas são distintas das do Cláudia; o cliente não escolhe seu papel. Veja `acessos-consultas.md` para ativação e para o fluxo rápido, sem cadastro livre na futura interface.

## Validação e limites

- Testes Dart cobrem regras puras, DTOs/repositórios com o SDK real e transporte HTTP simulado, composição Riverpod, erros e shell GoRouter.
- Testes em PostgreSQL embarcado executam a migração, RPCs, rollback e permissões reais de SQL/RLS usando um schema Auth mínimo de teste. Não substituem teste de concorrência com múltiplas conexões nem testes de Auth/Realtime no Supabase hospedado.
- A URL/chave pública fornecidas passaram em uma sonda somente de leitura de `/auth/v1/settings` (HTTP 200). Após o sucesso da migração informado pelo usuário, a consulta anônima de `phalanxes` retornou HTTP 401 / `42501`, confirmando a relação reconhecida e a ausência de grant anônimo. O banco é compartilhado com o Cláudia; o fluxo autenticado ainda precisa ser validado. Nenhuma conta ou dado remoto foi criado por essa sonda.
- Ainda faltam: relatórios e snapshots, estatísticas individuais, conclusão em lote com nota 0, dois fluxos de fechamento diário, limpeza/aviso de sessão anterior, adiamento da chamada da fila, gestão de falanges, recuperação de senha e administração de usuários. Este incremento não declara paridade completa com o React.

O protótipo anterior continua em `lib/legacy/local_app.dart`, `lib/presentation/catalog_page.dart` e nos stores SQLite, acessível somente pelo entrypoint `lib/main_legacy.dart`. Ele tem regras antigas e não deve ser ligado às novas telas nem tratado como fallback online. Seus bancos/outbox não foram apagados nem enviados ao Supabase.

## Referências técnicas

- [Inicialização Supabase Flutter](https://supabase.com/docs/reference/dart/initializing)
- [RPCs no SDK Dart](https://supabase.com/docs/reference/dart/rpc)
- [Funções e segurança no PostgreSQL/Supabase](https://supabase.com/docs/guides/database/functions)
- [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Testes de providers Riverpod](https://riverpod.dev/docs/how_to/testing)
