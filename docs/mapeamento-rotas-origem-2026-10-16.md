# Mapeamento de rotas e telas

**Revisado em:** 16/10/2026  
**Base:** rotas declaradas em `src/App.tsx` e navegação visível em `src/components/Layout.tsx`.

## Visão geral

O app usa React Router com rotas declaradas individualmente. A maioria das telas autenticadas é renderizada dentro do `Layout`, que exibe navegação lateral, seletor de núcleo e ação de sair. O login, a tela 404 e algumas rotas de perfil/seleção têm comportamento de layout próprio ou não usam o layout principal.

```text
/login
  └── login/cadastro/recuperação de senha
      └── após login → / (tablet → /feedback)
          └── botão de continuação, quando exibido:
              ├── tablet → /feedback
              ├── user → /consultation-room
              └── outros perfis → /

/nucleos → selecionar núcleo → /
  └── Início → /setup → /mediums → /consultation → /consultation-room

Menu lateral: /, /setup, /mediums, /consultation-room, /feedback,
              /medium-stats, /registration, /history, /admin, /stats, /reports
```

O diagrama representa os destinos principais identificados no código. A disponibilidade de links no menu não é idêntica à proteção de cada rota.

## Rotas registradas

| Rota | Tela/componente | Acesso aplicado pela rota | Layout | Função principal |
|---|---|---|---|---|
| `/login` | `Login` — `src/pages/Login.tsx` | Pública | Layout de login próprio | Seleção de núcleo para entrar, login, cadastro e recuperação de senha. Inclui opções de acesso rápido para os perfis cambono/tablet. |
| `/nucleos` | `NucleoSelector` — `src/pages/NucleoSelector.tsx` | Autenticado | `Layout` | Selecionar um núcleo; a interface de administrador também permite criar, editar e excluir núcleos. |
| `/` | `Index` — `src/pages/Index.tsx` | Autenticado e núcleo selecionado | `Layout` | Tela inicial com ação para iniciar o trabalho de consulta. Perfil tablet é redirecionado para `/feedback`. |
| `/profile` | `Profile` — `src/pages/Profile.tsx` | Autenticado | Sem `Layout` principal | Exibir e editar informações pessoais e interface para troca de senha. No código atual, os handlers de edição/troca mostram confirmação, mas não persistem as alterações no Firebase. |
| `/setup` | `ConsultationSetup` — `src/components/ConsultationSetup.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN`, `USER` ou `CAMBONO` | `Layout` | Definir falange, duração, limite e dirigente; administrar falanges e tratar consultas abertas/encerramento. |
| `/mediums` | `MediumAttendance` — `src/components/MediumAttendance.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN`, `USER` ou `CAMBONO` | `Layout` | Marcar presença dos médiuns e seguir para gestão de consultas. |
| `/consultation` | `Consultation` — `src/components/Consultation.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN`, `USER` ou `CAMBONO` | `Layout` | Abrir consulta, selecionar médium/guia e visualizar consultas ativas e fila. |
| `/consultation-room` | `ConsultationRoom` — `src/components/ConsultationRoom.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN`, `USER` ou `CAMBONO` | `Layout` | Monitorar sala, timers, fila, alertas, cancelamento e finalização do trabalho. |
| `/feedback` | `Feedback` — `src/components/Feedback.tsx` | Autenticado | `Layout` | Localizar consulta em andamento e registrar avaliação/comentário, concluindo-a. |
| `/medium-stats` | `MediumStats` — `src/pages/MediumStats.tsx` | Autenticado e `RoleGuard` com `MEDIUM`; a própria tela exige perfil `medium` exato | `Layout` | Mostrar estatísticas do médium associado ao usuário. |
| `/registration` | `MediumRegistration` — `src/components/MediumRegistration.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN` | `Layout` | Cadastrar, editar, desativar, reativar e remover médiuns, incluindo guias e núcleos associados. |
| `/history` | `History` — `src/components/History.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN` | `Layout` | Consultar o histórico de atendimentos e filtrar/agrupar registros por período. |
| `/admin` | `Admin` — `src/pages/Admin.tsx` | Autenticado e `RoleGuard` com `ADMIN` | `Layout` | Ferramentas administrativas: operações sobre consultas/histórico, dados, backup, sessões, logs e monitores. |
| `/stats` | `GlobalStats` — `src/pages/GlobalStats.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN` | `Layout` | Exibir indicadores globais acumulados por médium e guia. |
| `/reports` | `Reports` — `src/pages/Reports.tsx` | Autenticado, núcleo selecionado e `RoleGuard` com `ADMIN` | `Layout` | Consultar, filtrar, avaliar e exportar relatórios. |
| Qualquer outra rota | `NotFound` — `src/pages/NotFound.tsx` | Sem guard de autenticação na declaração | Tela própria | Exibir 404 e registrar a rota inexistente no log. |

## Controles de navegação e redirecionamento

### Autenticação e núcleo

- `ProtectedRoute` redireciona para `/login` quando não há autenticação.
- `RequireNucleo` aguarda o carregamento da seleção e redireciona para `/nucleos` se nenhum núcleo estiver selecionado.
- `/setup`, `/mediums`, `/consultation`, `/consultation-room`, `/registration`, `/history`, `/stats` e `/reports` exigem núcleo selecionado.
- `/profile`, `/feedback`, `/admin` e `/nucleos` não passam pelo `RequireNucleo`.
- A rota `/` passa por `RequireNucleo` antes de avaliar o redirecionamento de tablet para `/feedback`.

### Perfil e autorização na interface

O menu lateral filtra seus itens por perfil usando correspondência exata com os perfis listados para cada item. Já `RoleGuard` compara níveis hierárquicos: `admin` (4), `user` (3), `cambono` (2), `medium` (2) e `tablet` (1). Portanto, uma rota cuja lista contém `CAMBONO` aceita também `medium` no guard, mesmo que o menu não mostre o link para esse perfil. `/medium-stats` faz uma checagem adicional de perfil exato no componente da página.

Esses guards são controles de interface e não substituem regras de segurança no Firebase.

## Itens do menu lateral

| Item | Destino | Perfis listados no menu |
|---|---|---|
| Início | `/` | `admin`, `user`, `tablet`, `medium`, `cambono` |
| Configuração | `/setup` | `admin`, `user`, `cambono` |
| Presença de Médiuns | `/mediums` | `admin`, `user`, `cambono` |
| Sala de Consultas | `/consultation-room` | `admin`, `user`, `cambono` |
| Feedback | `/feedback` | `admin`, `tablet`, `cambono` |
| Minhas Estatísticas | `/medium-stats` | `medium` |
| Registro de Médiuns | `/registration` | `admin` |
| Histórico | `/history` | `admin` |
| Administração | `/admin` | `admin` |
| Estatísticas Globais | `/stats` | `admin` |
| Relatórios | `/reports` | `admin` |

`/consultation` está registrada, mas não consta no menu lateral. A tela de presença encaminha para ela. `/feedback` é uma rota própria, disponível pelo menu aos perfis que têm esse item e pelo redirecionamento de tablet após login.

O seletor de núcleo no layout permite trocar diretamente entre núcleos carregados ou limpar a seleção e voltar para `/nucleos`. A ação “Sair” encerra a sessão e navega para `/login`.

## Fluxos principais

### Acesso ao app

1. O usuário abre `/login` e pode escolher núcleo, usar acesso rápido ou informar credenciais.
2. Após login normal, perfil tablet segue para `/feedback` e os demais perfis seguem para `/`. Quando a tela de login autenticado oferece o botão de continuação, esse botão encaminha tablet para `/feedback`, perfil `user` para `/consultation-room` e os demais para `/`.
3. Rotas operacionais sem núcleo selecionado encaminham para `/nucleos`.

### Trabalho de consultas

1. `/` → iniciar trabalho → `/setup`.
2. Salvar a configuração encaminha para `/mediums`.
3. A tela de presença encaminha para `/consultation`.
4. `/consultation` permite gerir abertura/fila; `/consultation-room` monitora atendimentos e oferece recursos da sala.
5. `/feedback` localiza a consulta aberta e conclui com avaliação.

### Administração

Pelo menu lateral do administrador, as telas ficam disponíveis em `/registration`, `/history`, `/admin`, `/stats` e `/reports`, sujeitas também à seleção de núcleo nas rotas que declaram `RequireNucleo`.

## Fontes no código

- Definição de rotas e guards: [App.tsx](../src/App.tsx)
- Menu, seletor de núcleo e logout: [Layout.tsx](../src/components/Layout.tsx)
- Controle hierárquico de perfil: [RoleGuard.tsx](../src/components/RoleGuard.tsx)
- Destinos pós-login: [Login.tsx](../src/pages/Login.tsx)
- Encadeamento da configuração e presença: [ConsultationSetup.tsx](../src/components/ConsultationSetup.tsx), [MediumAttendance.tsx](../src/components/MediumAttendance.tsx)
