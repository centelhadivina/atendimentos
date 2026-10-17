-- Aplicar depois de 202610160002. Define somente acessos do Consultas.
-- Não cria contas Auth, não envia emails e não altera usuarios_sistema/Cláudia.
begin;
do $$ begin
  if to_regclass('public.profiles') is null then raise exception 'Aplique primeiro a migração 202610160002.'; end if;
  if not exists(select 1 from public.nucleos where cod='001' and upper(sigla)='CCU')
    or not exists(select 1 from public.nucleos where cod='002' and upper(sigla)='CPO') then
    raise exception 'Os vínculos CCU=001 e CPO=002 precisam corresponder ao cadastro compartilhado.';
  end if;
end $$;
create table app_private.consultation_accounts (
  email text primary key check(email=lower(btrim(email))),
  role text not null check(role in ('admin','cambono','tablet')),
  name text not null, nucleo_id text references public.nucleos(cod),
  check((role='admin' and nucleo_id is null) or (role<>'admin' and nucleo_id is not null))
);
insert into app_private.consultation_accounts(email,role,name,nucleo_id) values
  ('cinthiadutra@gmail.com','admin','Cinthia Dutra',null),
  ('ccu.acentelhadivina@gmail.com','cambono','Cambono CCU','001'),
  ('tecnologia.ccu@gmail.com','tablet','Tablet CCU','001'),
  ('cpo.acentelhadivina@gmail.com','cambono','Cambono CPO','002'),
  ('tecnologia.cpo@outlook.com','tablet','Tablet CPO','002');
revoke all on app_private.consultation_accounts from public,anon,authenticated;

create function app_private.has_consultation_access() returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from auth.users u join app_private.consultation_accounts a on a.email=lower(btrim(u.email))
    join public.profiles p on p.id=u.id and p.role=a.role
    where u.id=auth.uid() and u.email_confirmed_at is not null)
$$;
create or replace function app_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
  select app_private.has_consultation_access() and exists(select 1 from public.profiles where id=auth.uid() and role='admin')
$$;
create or replace function app_private.can_access(p_nucleo_id text) returns boolean language sql stable security definer set search_path='' as $$
  select app_private.has_consultation_access() and (app_private.is_admin() or exists(
    select 1 from public.user_nucleos un join auth.users u on u.id=un.user_id
    join app_private.consultation_accounts a on a.email=lower(btrim(u.email)) and a.nucleo_id=un.nucleo_id
    where un.user_id=auth.uid() and un.nucleo_id=p_nucleo_id))
$$;

create function app_private.sync_consultation_account(p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare a app_private.consultation_accounts; u auth.users;
begin
  select * into u from auth.users where id=p_user_id;
  if not found or u.email_confirmed_at is null then return; end if;
  select * into a from app_private.consultation_accounts where email=lower(btrim(u.email));
  if not found then return; end if;
  insert into public.profiles(id,name,role) values(u.id,a.name,a.role)
    on conflict(id) do update set role=excluded.role, name=case when btrim(profiles.name)='' then excluded.name else profiles.name end,updated_at=now();
  if a.nucleo_id is not null then
    insert into public.user_nucleos(user_id,nucleo_id) values(u.id,a.nucleo_id) on conflict do nothing;
  end if;
end $$;
create or replace function app_private.create_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform app_private.sync_consultation_account(new.id);
  return new;
end $$;
-- O trigger de INSERT instalado na migração anterior permanece.
create trigger sync_consultation_account_after_confirmation after update of email,email_confirmed_at on auth.users
  for each row execute function app_private.create_profile();
-- Liga somente as cinco contas autorizadas que já existirem e estiverem confirmadas.
do $$ declare account_id uuid; begin
  for account_id in select u.id from auth.users u join app_private.consultation_accounts a on a.email=lower(btrim(u.email)) loop
    perform app_private.sync_consultation_account(account_id);
  end loop;
end $$;

-- Usuários do Cláudia não ganham acesso ao módulo por terem uma conta no mesmo Auth.
alter policy read_profiles on public.profiles using(app_private.has_consultation_access() and (id=auth.uid() or app_private.is_admin()));
alter policy read_user_nucleos on public.user_nucleos using(app_private.has_consultation_access() and (user_id=auth.uid() or app_private.is_admin()));
alter policy read_phalanxes on public.phalanxes using(app_private.has_consultation_access());
create function public.my_consultation_profile() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode='28000',message='Entre para continuar.'; end if;
  if not app_private.has_consultation_access() then raise insufficient_privilege using message='Conta sem acesso ao Consultas.'; end if;
  select to_jsonb(p) || jsonb_build_object('email',u.email,'user_nucleos',coalesce((select jsonb_agg(jsonb_build_object('nucleo_id',un.nucleo_id) order by un.nucleo_id) from public.user_nucleos un where un.user_id=p.id),'[]'::jsonb))
    into result from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid();
  return result;
end $$;
revoke execute on function app_private.has_consultation_access(),app_private.sync_consultation_account(uuid) from public,anon,authenticated;
grant execute on function app_private.has_consultation_access() to authenticated;
revoke execute on function public.my_consultation_profile() from public,anon;
grant execute on function public.my_consultation_profile() to authenticated;
notify pgrst,'reload schema';
commit;
