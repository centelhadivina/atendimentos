# Acessos do Consultas, separados do Cláudia

Decisão do usuário em 16/10/2026: manter os acessos já usados no Firebase/React, com os atalhos de cambono/tablet e `cinthiadutra@gmail.com` como master admin do Consultas. A autenticação do Cláudia e sua tabela `usuarios_sistema` continuam independentes. Compartilhar o Supabase não concede acesso automático entre os módulos.

## Contas iniciais

| Núcleo | Código Supabase confirmado | Perfil | Conta existente no React |
| --- | --- | --- | --- |
| CCU | `001` | cambono | `ccu.acentelhadivina@gmail.com` |
| CCU | `001` | tablet | `tecnologia.ccu@gmail.com` |
| CPO | `002` | cambono | `cpo.acentelhadivina@gmail.com` |
| CPO | `002` | tablet | `tecnologia.cpo@outlook.com` |
| Todos | — | admin | `cinthiadutra@gmail.com` |

Emails e seleção núcleo/perfil foram conferidos no React. Códigos/siglas foram consultados no cadastro compartilhado. As senhas fornecidas pelo usuário não foram adicionadas ao código, assets, dart-defines ou a arquivos versionados.

Esses são os cinco acessos iniciais, não cinco contas novas por instalação. Outros usuários já existentes no Firebase poderão ser aprovados explicitamente depois. A futura interface não terá cadastro livre. O comando de cadastro foi retirado da camada de apresentação/aplicação; o datasource técnico de cadastro permanece disponível para testes e cenários administrativos futuros, sem concessão de acesso ao módulo.

## Fluxo preparado

1. Operador escolhe núcleo e cambono/tablet.
2. O app chama a Edge Function `consultation-quick-access` enviando somente `nucleo_id` e `role`.
3. O backend escolhe uma das quatro contas fixas e usa o segredo do núcleo para autenticar no Supabase Auth. Não aceita email ou senha arbitrários do cliente, nem perfil admin.
4. O backend valida o perfil/núcleo no banco. Somente então devolve um refresh token ao cliente, com resposta `no-store`.
5. O SDK troca o token por uma sessão, persiste e renova essa sessão. Nas próximas aberturas, a sessão é restaurada, sem criar conta nova ou exigir login adicional enquanto ela for válida.
6. Admin entra pelo login normal. O banco exige o email master confirmado; escolher `admin` em metadados ou no cliente não concede privilégios.

A função é uma **entrada pública para contas compartilhadas**, assim como os atalhos do React. Qualquer pessoa com acesso a esse fluxo poderá obter a sessão operacional correspondente; esconder a senha no backend não torna esse acesso individual. O admin não está exposto nesse atalho. Se futuramente for necessária identificação individual do operador, será outro requisito de acesso.

A sessão local do Flutter usa a chave própria `centelha-consultas-auth-v1`; logout usa escopo `local`, preservando outras sessões da mesma conta. No Web, isso separa a persistência padrão; o SDK também possui mecanismos de comunicação entre abas. Caso ambos os apps sejam hospedados na mesma origem, o comportamento entre abas deverá ser validado antes de declarar isolamento completo das sessões.

## Migração adicional necessária

Aplicar **uma vez**, depois da migração 002 já executada:

`supabase/migrations/202610160003_consultation_accounts.sql`

Ela configura a allowlist privada dos cinco emails, vínculos de núcleo e o perfil master. Contas existentes e confirmadas são ligadas imediatamente. Contas aprovadas criadas/confirmadas depois são ligadas por trigger. Não cria contas Auth, não envia emails, não importa hashes Firebase e não altera `usuarios_sistema` ou permissões do Cláudia.

A migração também protege as leituras do módulo para que uma conta Auth do Cláudia não tenha acesso a Consultas só por estar no mesmo projeto. Os registros de perfil anteriormente criados não são apagados; a autorização passa a exigir conta aprovada, email verificado e papel correspondente. Login normal e rápido verificam `my_consultation_profile()`.

Conferência no SQL Editor (somente os cinco emails previstos):

```sql
select a.email,a.role,a.nucleo_id,
       u.id is not null as existe_no_auth,
       u.email_confirmed_at is not null as email_confirmado
from app_private.consultation_accounts a
left join auth.users u on lower(btrim(u.email))=a.email
order by a.email;
```

## Provisionar/reaproveitar contas no Auth

Um teste com as quatro credenciais informadas retornou `invalid_credentials` no Supabase. Isso não distingue conta ausente de senha diferente. Nenhuma conta foi criada ou modificada nesse teste.

Opções administrativas:

- Usar Authentication > Users no Dashboard para criar apenas as contas ausentes, com os mesmos emails e credenciais desejadas. O master mantém seu login normal; não gerar uma senha nova aleatória para ele.
- Usar `tool/provision_consultation_accounts.py`: plano por padrão, sem rede. Com `--apply`, requer `SUPABASE_SECRET_KEY` somente no ambiente administrativo local. Lista as contas via Admin API, reutiliza as existentes sem alterar senhas e cria apenas as ausentes. A criação usa confirmação administrativa, sem convite/email. Uma conta existente ainda não confirmada é apenas reportada, sem modificação.

```sh
python3 tool/provision_consultation_accounts.py
# Após configurar o segredo administrativo no ambiente local:
python3 tool/provision_consultation_accounts.py --apply --env-file config/consultation-secrets.env
```

O arquivo local contém as duas senhas de núcleo, usando as variáveis abaixo. Para criar o master caso ele não exista, é necessário definir `CONSULTAS_MASTER_PASSWORD` apenas no ambiente administrativo ou criá-lo no Dashboard. Não enviar senhas/chaves administrativas no chat e não configurar esses segredos no Flutter.

Contas já existentes nunca têm senha alterada pelo script. Se uma dessas contas tiver outra senha no Supabase, é preciso decidir administrativamente a credencial de referência antes de ativar o atalho.

## Publicar o backend de acesso rápido

A função está preparada em `supabase/functions/consultation-quick-access`. Requer autenticação administrativa do Supabase CLI para publicar; a chave pública do app não permite o deploy.

1. Copiar `config/consultation-secrets.example.env` para `config/consultation-secrets.env` (ignorado pelo Git).
2. Preencher `CONSULTAS_CCU_PASSWORD` e `CONSULTAS_CPO_PASSWORD` com as credenciais das contas do respectivo núcleo. A configuração mantém o compartilhamento por núcleo existente no React.
3. Não colocar chave administrativa nem senha do master nesse arquivo de secrets da função.
4. Publicar secrets e função:

```sh
supabase secrets set --env-file config/consultation-secrets.env --project-ref lnzhgnwwzvpplhaxqbvq
supabase functions deploy consultation-quick-access --project-ref lnzhgnwwzvpplhaxqbvq --no-verify-jwt
```

`verify_jwt=false` é necessário para o atalho funcionar antes de haver sessão, e está configurado somente para essa função. O backend usa o Auth normal e a autorização do banco para as contas fixas; não usa `service_role` para atender o atalho.

## Estado da entrega

Implementados e testados localmente: migração de acessos, handler Edge, datasource/repositório, casos de uso, comandos Riverpod, persistência de sessão e ferramenta administrativa. A migração 003, o provisionamento e o deploy da função **ainda não foram executados no projeto remoto**. As telas continuam sendo a próxima etapa.

## Testes

```sh
flutter analyze
flutter test
node supabase/tests/quick_access.mjs
PGLITE_MODULE=/tmp/centelha-pg-validation/node_modules/@electric-sql/pglite/dist/index.js node supabase/tests/consultation_accounts.mjs
python3 -m unittest discover -s test -p '*_test.py'
```

Testes de Auth no PostgreSQL usam fixture, não o serviço hospedado. O handler é testado com transporte HTTP simulado. Ainda é necessário validar o fluxo completo após a publicação e as credenciais existentes no Supabase.

Referências: [Admin API de criação de usuários](https://supabase.com/docs/reference/javascript/auth-admin-createuser), [configuração de Edge Functions](https://supabase.com/docs/guides/functions/function-configuration), [segurança/autenticação das funções](https://supabase.com/docs/guides/functions/auth).
