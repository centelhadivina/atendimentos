# Integração relacional com o Cláudia

Confirmado pelo usuário em 16/10/2026: o projeto Supabase já pertence ao sistema **Cláudia**. Centelha Consultas é um módulo a integrar a esse banco, não um banco organizacional separado. A migração de adaptação foi executada com sucesso informado pelo usuário.

## O que já está relacionado

`nucleos.cod` é reutilizado, sem duplicar o cadastro organizacional. As tabelas novas de acesso, vínculos de médiuns, sessões e consultas referenciam esse código textual, preservando zeros à esquerda. A descrição específica do módulo fica em `consultation_nucleo_details`.

A API reconhece `phalanxes` e nega leitura sem usuário autenticado. Essa verificação confirma a existência da relação e os grants anônimos, não o funcionamento completo de Auth, RPCs ou de todos os vínculos.

## Separação de usuários confirmada

O usuário esclareceu que os usuários do Consultas são diferentes dos usuários do Cláudia. O Consultas mantém os acessos Firebase existentes: cambono/tablet por núcleo e `cinthiadutra@gmail.com` como master admin. Não unificar `profiles` com `usuarios_sistema` nem converter os níveis do Cláudia em papéis do Consultas. A configuração preparada está em [acessos-consultas.md](acessos-consultas.md).

A normalização futura pode relacionar dados de pessoas, médiuns e guias com as tabelas do Cláudia; isso não implica compartilhar autorização ou alterar o fluxo de login. Os cinco acessos iniciais continuam sendo reutilizados, sem criar conta por dispositivo.

## Relações de dados ainda a definir

| Conceito | Estrutura conhecida do Cláudia | Ponto a confirmar |
| --- | --- | --- |
| Pessoa/médium | `usuarios.id`, `usuarios.numero_cadastro`; `dados_mediunicos.membro_id` | Qual ID é a referência canônica e como `membro_id` se relaciona com ela |
| Dados mediúnicos/guias | `dados_mediunicos`, nomes por falange e dados históricos | Quais campos são a fonte atual e quais são snapshots históricos |
| Consulente | `usuarios` e `consultas.cadastro_consulente` | Se o consulente pode ser visitante sem cadastro e quando existe vínculo explícito |
| Acesso ao aplicativo | `auth.users` e `profiles` do Consultas | Separado de `usuarios_sistema`; preservar os acessos e fluxo Firebase existentes |
| Notas/histórico | `nota_consultas`, `consultas`, novas `consultations` | Diferenças de escala e semântica; não transformar nota 0–10 em 1–5 automaticamente |

O schema informado não comprova equivalência entre `usuarios.id`, `usuarios.numero_cadastro`, `dados_mediunicos.membro_id`, `usuarios_sistema.id` e `auth.users.id`. Não associar pessoas ou contas por coincidência de nome/email, não inferir privilégios e não importar registros sem regras explícitas.

## Implementação prevista

1. Definir, para cada relação, a tabela responsável pelo cadastro, a chave estável, a cardinalidade e o comportamento quando o vínculo não existe.
2. Acrescentar FKs ou tabelas de associação por migrações aditivas, após validar tipos e referências existentes. Dados históricos devem manter seus snapshots.
3. Adaptar os datasources/repositórios para consultar e escrever cada dado na sua fonte definida, mantendo domínio e casos de uso independentes do schema físico.
4. Testar operações em ambos os módulos para verificar consistência e permissões. Depois, ligar as telas aos contratos.

A implementação atual ainda possui seu agregado operacional de médiuns/guias. Ele não é sincronizado automaticamente com `usuarios` ou `dados_mediunicos`. A decisão sobre cadastro compartilhado deve ser resolvida antes de alimentar esses agregados com os mesmos dados reais em paralelo.

A confirmação de banco compartilhado não altera a direção: um app Android/Windows/Web, Clean Architecture, SOLID, Riverpod e GoRouter; online com Supabase primeiro, offline com SQLite depois.
