-- CORREÇÃO PARA O PROJETO EXISTENTE: executar este arquivo SOZINHO.
-- Substitui o bootstrap 202610160001 neste projeto (não executar os dois).
-- Reutiliza public.nucleos(cod,sigla,nome). Não altera sua estrutura,
-- policies, grants, índices ou triggers; não toca usuarios/consultas/nota_consultas.
begin;
do $$
declare conflicts text;
begin
  if to_regclass('public.nucleos') is null then raise exception 'Cadastro compartilhado public.nucleos não encontrado. Use o bootstrap de base nova.'; end if;
  if exists(select 1 from (values ('cod','varchar'),('sigla','varchar'),('nome','varchar'),('ativo','bool'),('created_at','timestamptz'),('updated_at','timestamptz')) expected(name,kind)
    where not exists(select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'nucleos' and c.column_name = expected.name and c.udt_name = expected.kind)) then
    raise exception 'public.nucleos difere do diagnóstico fornecido. Nenhuma adaptação foi aplicada.';
  end if;
  if not exists(select 1 from pg_constraint con where con.conrelid = 'public.nucleos'::regclass and con.contype = 'p' and pg_get_constraintdef(con.oid) = 'PRIMARY KEY (cod)') then raise exception 'A chave primária de public.nucleos precisa ser cod.'; end if;
  select string_agg(c.relname,', ' order by c.relname) into conflicts from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('profiles','consultation_nucleo_details','user_nucleos','phalanxes','mediums','medium_nucleos','guides','work_sessions','attendance','consultations');
  if conflicts is not null then raise exception 'Objetos do módulo já existem: %. A execução foi interrompida sem alterar dados.',conflicts; end if;
end $$;

-- Núcleo online. Escritas de negócio somente por RPCs transacionais.
create schema if not exists app_private;
revoke all on schema app_private from public;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  role text not null default 'user' check (role in ('admin','user','tablet','medium','cambono')),
  medium_id uuid, photo_url text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
-- Extensão do módulo: public.nucleos permanece intacta, com PK cod em texto.
create table public.consultation_nucleo_details (
  nucleo_id text primary key references public.nucleos(cod),
  description text not null default ''
);
create table public.user_nucleos (
  user_id uuid not null references public.profiles(id) on delete cascade,
  nucleo_id text not null references public.nucleos(cod), primary key(user_id,nucleo_id)
);
create table public.phalanxes (
  id uuid primary key default gen_random_uuid(), name text not null unique check (btrim(name) <> ''),
  required_for_registration boolean not null default false, position integer not null
);
insert into public.phalanxes(name, required_for_registration, position) values
  ('Exus e Pombogiras',true,1), ('Caboclos e Caboclas',true,2), ('Baianos e Baianas',true,3),
  ('Ciganos e Ciganas',true,4), ('Malandros e Malandras',true,5), ('Marinheiros',true,6),
  ('Preto-velhos e Preta-velhas',true,7);
create table public.mediums (
  id uuid primary key default gen_random_uuid(), name text not null check(btrim(name) <> ''),
  degree text not null check(degree in ('medium','dirigente')),
  ribbon text not null check(ribbon in ('yellow','green','blue','indigo','purple','colorful','white')),
  active boolean not null default true, inactive_reason text, inactivated_at timestamptz,
  inactivated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (active or (btrim(inactive_reason) <> '' and inactivated_at is not null))
);
alter table public.profiles add constraint profiles_medium_id_fkey foreign key(medium_id) references public.mediums(id);
create unique index mediums_normalized_name on public.mediums(lower(btrim(name)));
create table public.medium_nucleos (
  medium_id uuid not null references public.mediums(id), nucleo_id text not null references public.nucleos(cod),
  primary key(medium_id,nucleo_id)
);
create table public.guides (
  id uuid primary key default gen_random_uuid(), medium_id uuid not null references public.mediums(id),
  name text not null check(btrim(name) <> ''), phalanx_id uuid not null references public.phalanxes(id),
  unique(medium_id,phalanx_id), unique(id,medium_id)
);
create table public.work_sessions (
  id uuid primary key default gen_random_uuid(), nucleo_id text not null references public.nucleos(cod),
  work_day date not null, phalanx_id uuid not null references public.phalanxes(id),
  duration_minutes integer not null default 30 check(duration_minutes >= 30),
  consultation_limit integer not null default 3 check(consultation_limit >= 3),
  dirigent_id uuid references public.mediums(id), locked_at timestamptz,
  unique(nucleo_id, work_day), unique(id,nucleo_id)
);
create table public.attendance (
  session_id uuid not null references public.work_sessions(id), medium_id uuid not null references public.mediums(id),
  present boolean not null default false, updated_at timestamptz not null default now(),
  primary key(session_id,medium_id)
);
create table public.consultations (
  id uuid primary key default gen_random_uuid(), session_id uuid not null, nucleo_id text not null,
  medium_id uuid not null references public.mediums(id), guide_id uuid not null,
  password text not null check(password ~ '^(0|[1-9][0-9]{0,3})[a-z]?$'),
  consultant_name text not null check(btrim(consultant_name) <> ''),
  status text not null check(status in ('waiting','queue','in_progress','completed','cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  started_at timestamptz, ended_at timestamptz, duration_minutes integer not null check(duration_minutes >= 30),
  service_minutes integer check(service_minutes >= 0), rating integer check(rating between 0 and 5), feedback text,
  is_test boolean not null default false, is_extra boolean not null default false,
  override_reason text, exceeded_by integer not null default 0 check(exceeded_by >= 0),
  medium_name text not null, guide_name text not null, phalanx_id uuid not null references public.phalanxes(id),
  dirigent_id uuid references public.mediums(id), dirigent_name text, queued_at timestamptz,
  foreign key(session_id,nucleo_id) references public.work_sessions(id,nucleo_id),
  foreign key(guide_id,medium_id) references public.guides(id,medium_id),
  unique(session_id,password),
  check(status <> 'in_progress' or (started_at is not null and ended_at is null)),
  check(status <> 'completed' or (started_at is not null and ended_at is not null and rating is not null))
);
create unique index one_active_consultation_per_medium on public.consultations(medium_id) where status = 'in_progress';
create index consultations_queue on public.consultations(session_id,medium_id,created_at,id) where status in ('waiting','queue');
create index consultations_feedback on public.consultations(nucleo_id,status);
create index medium_nucleos_nucleo on public.medium_nucleos(nucleo_id,medium_id);

create function app_private.create_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id,name) values(new.id,coalesce(new.raw_user_meta_data->>'name',''));
  return new;
end $$;
create trigger create_profile after insert on auth.users for each row execute function app_private.create_profile();
-- Contas já existentes também recebem o perfil básico, sem promoção automática.
insert into public.profiles(id,name) select id,coalesce(raw_user_meta_data->>'name','') from auth.users on conflict do nothing;

create function app_private.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
$$;
create function app_private.can_access(p_nucleo_id text) returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (app_private.is_admin() or exists(select 1 from public.user_nucleos where user_id = auth.uid() and nucleo_id = p_nucleo_id))
$$;
create function app_private.require_access(p_nucleo_id text, p_feedback boolean default false) returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not app_private.can_access(p_nucleo_id) or not exists(select 1 from public.profiles where id = auth.uid() and (role in ('admin','user','cambono') or (p_feedback and role = 'tablet'))) then
    raise insufficient_privilege using message = 'Acesso não autorizado ao núcleo.';
  end if;
end $$;
create function app_private.require_admin() returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not app_private.is_admin() then raise insufficient_privilege using message = 'Acesso administrativo necessário.'; end if;
end $$;
create function app_private.work_day() returns date language sql stable set search_path = '' as $$
  select ((now() at time zone 'America/Sao_Paulo') - interval '3 hours')::date
$$;
create function app_private.current_session(p_id uuid) returns public.work_sessions language plpgsql security definer set search_path = '' as $$
declare s public.work_sessions;
begin
  select * into strict s from public.work_sessions where id = p_id for update;
  perform app_private.require_access(s.nucleo_id);
  if s.work_day <> app_private.work_day() then raise exception 'Selecione a sessão atual.'; end if;
  return s;
exception when no_data_found then raise exception using errcode = 'CC404', message = 'Sessão não encontrada.';
end $$;
create function app_private.check_medium(p_session public.work_sessions, p_medium_id uuid, p_guide_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  -- Todos os caminhos de ocupação usam o mesmo lock por médium.
  perform 1 from public.mediums where id = p_medium_id and active for update;
  if not found then raise exception 'Médium inativo ou inexistente.'; end if;
  if not exists(select 1 from public.medium_nucleos where medium_id = p_medium_id and nucleo_id = p_session.nucleo_id) then raise exception 'Médium não pertence ao núcleo.'; end if;
  if not exists(select 1 from public.attendance where session_id = p_session.id and medium_id = p_medium_id and present) then raise exception 'Médium ausente nesta sessão.'; end if;
  if not exists(select 1 from public.guides where id = p_guide_id and medium_id = p_medium_id and phalanx_id = p_session.phalanx_id) then raise exception 'Guia inválido para o médium ou falange do dia.'; end if;
end $$;
create function app_private.normalize_password(p_password text) returns text language plpgsql immutable set search_path = '' as $$
declare v text := lower(btrim(p_password));
begin
  if v is null or v !~ '^[0-9]{1,4}[a-z]?$' then raise exception 'Senha inválida: use até quatro algarismos e uma letra opcional.'; end if;
  return (substring(v from '^[0-9]+')::integer)::text || coalesce(substring(v from '[a-z]$'),'');
end $$;

-- RLS para leituras; nenhuma escrita direta é concedida ao cliente.
alter table public.profiles enable row level security;
alter table public.user_nucleos enable row level security;
alter table public.consultation_nucleo_details enable row level security;
alter table public.phalanxes enable row level security;
alter table public.mediums enable row level security;
alter table public.medium_nucleos enable row level security;
alter table public.guides enable row level security;
alter table public.work_sessions enable row level security;
alter table public.attendance enable row level security;
alter table public.consultations enable row level security;
create policy read_profiles on public.profiles for select to authenticated using(id = auth.uid() or app_private.is_admin());
create policy read_user_nucleos on public.user_nucleos for select to authenticated using(user_id = auth.uid() or app_private.is_admin());
create policy read_nucleo_details on public.consultation_nucleo_details for select to authenticated using(app_private.can_access(nucleo_id));
create policy read_phalanxes on public.phalanxes for select to authenticated using(auth.uid() is not null);
create policy read_mediums on public.mediums for select to authenticated using(app_private.is_admin() or exists(select 1 from public.medium_nucleos mn where mn.medium_id = id and app_private.can_access(mn.nucleo_id)));
create policy read_medium_nucleos on public.medium_nucleos for select to authenticated using(app_private.can_access(nucleo_id));
create policy read_guides on public.guides for select to authenticated using(exists(select 1 from public.mediums m where m.id = medium_id));
create policy read_sessions on public.work_sessions for select to authenticated using(app_private.can_access(nucleo_id));
create policy read_attendance on public.attendance for select to authenticated using(exists(select 1 from public.work_sessions s where s.id = session_id));
create policy read_consultations on public.consultations for select to authenticated using(app_private.can_access(nucleo_id) and exists(select 1 from public.profiles p where p.id = auth.uid() and (p.role in ('admin','user','cambono') or (p.role = 'tablet' and status = 'in_progress'))));
-- As funções de políticas precisam ser executáveis, mas não ficam no schema exposto pela API.
grant usage on schema app_private to authenticated;
grant execute on function app_private.is_admin(), app_private.can_access(text) to authenticated;

create function public.list_consultation_nucleos() returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',n.cod,'code',n.cod,'abbreviation',n.sigla,'name',n.nome,
    'description',coalesce(d.description,''),'active',coalesce(n.ativo,true),
    'created_at',n.created_at,'updated_at',n.updated_at)
  from public.nucleos n left join public.consultation_nucleo_details d on d.nucleo_id = n.cod
  where app_private.can_access(n.cod) order by n.nome,n.cod
$$;
revoke execute on function public.list_consultation_nucleos() from public,anon;
grant execute on function public.list_consultation_nucleos() to authenticated;

create function public.save_nucleo(p_data jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.nucleos; v_id text := nullif(btrim(p_data->>'id'),'');
  code text := nullif(btrim(p_data->>'code'),''); abbreviation text := nullif(btrim(p_data->>'abbreviation'),'');
  description text := coalesce(btrim(p_data->>'description'),'');
begin
  perform app_private.require_admin();
  if coalesce(btrim(p_data->>'name'),'') = '' then raise exception 'Informe o nome do núcleo.'; end if;
  if v_id is null then
    if code is null or abbreviation is null then raise exception 'O cadastro compartilhado exige código e sigla para criar um núcleo.'; end if;
    insert into public.nucleos(cod,sigla,nome) values(code,abbreviation,btrim(p_data->>'name')) returning * into r;
  else
    if code is not null and code <> v_id then raise exception 'O código do núcleo existente não pode ser alterado.'; end if;
    update public.nucleos set nome = btrim(p_data->>'name'), sigla = coalesce(abbreviation,sigla), updated_at = now() where cod = v_id returning * into r;
    if not found then raise exception using errcode = 'CC404', message = 'Núcleo não encontrado.'; end if;
  end if;
  insert into public.consultation_nucleo_details(nucleo_id,description) values(r.cod,description)
    on conflict(nucleo_id) do update set description = excluded.description;
  return jsonb_build_object('id',r.cod,'code',r.cod,'abbreviation',r.sigla,'name',r.nome,
    'description',description,'active',coalesce(r.ativo,true),'created_at',r.created_at,'updated_at',r.updated_at);
end $$;

create function public.save_medium(p_data jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (p_data->>'id')::uuid; g jsonb; r public.mediums; guide_ids uuid[] := '{}'; gid uuid;
begin
  perform app_private.require_admin();
  if coalesce(jsonb_array_length(p_data->'nucleo_ids'),0) = 0 then raise exception 'Selecione ao menos um núcleo.'; end if;
  if exists(select 1 from jsonb_array_elements(p_data->'guides') x group by x->>'phalanx_id' having count(*) > 1) then raise exception 'Apenas um guia por falange é permitido.'; end if;
  if exists(select 1 from public.phalanxes p where required_for_registration and not exists(select 1 from jsonb_array_elements(p_data->'guides') x where (x->>'phalanx_id')::uuid = p.id)) then raise exception 'Cadastre um guia para cada falange obrigatória.'; end if;
  if v_id is null then
    insert into public.mediums(name,degree,ribbon) values(btrim(p_data->>'name'),p_data->>'degree',p_data->>'ribbon') returning * into r;
    v_id := r.id;
  else
    perform 1 from public.mediums where id = v_id for update;
    if not found then raise exception using errcode = 'CC404', message = 'Médium não encontrado.'; end if;
    if exists(select 1 from public.consultations where medium_id = v_id and status in ('waiting','queue','in_progress')) then raise exception 'Médium possui consultas pendentes.'; end if;
    if p_data->>'degree' <> 'dirigente' and exists(select 1 from public.work_sessions where dirigent_id = v_id and work_day = app_private.work_day()) then raise exception 'Altere primeiro o dirigente na configuração.'; end if;
    update public.mediums set name = btrim(p_data->>'name'), degree = p_data->>'degree', ribbon = p_data->>'ribbon', updated_at = now() where id = v_id returning * into r;
  end if;
  delete from public.medium_nucleos where medium_id = v_id;
  insert into public.medium_nucleos(medium_id,nucleo_id) select v_id, value from jsonb_array_elements_text(p_data->'nucleo_ids') group by value;
  if exists(select 1 from public.work_sessions s where s.dirigent_id = v_id and s.work_day = app_private.work_day() and not exists(select 1 from public.medium_nucleos mn where mn.medium_id = v_id and mn.nucleo_id = s.nucleo_id)) then raise exception 'O dirigente deve continuar vinculado ao núcleo da sessão.'; end if;
  for g in select * from jsonb_array_elements(p_data->'guides') loop
    gid := (g->>'id')::uuid;
    if gid is null then
      -- Reaproveita ID por falange quando o formulário não fornece o ID antigo.
      select id into gid from public.guides where medium_id = v_id and phalanx_id = (g->>'phalanx_id')::uuid;
      gid := coalesce(gid,gen_random_uuid());
    elsif exists(select 1 from public.guides where id = gid and medium_id <> v_id) then raise exception 'Guia pertence a outro médium.';
    end if;
    insert into public.guides(id,medium_id,name,phalanx_id) values(gid,v_id,btrim(g->>'name'),(g->>'phalanx_id')::uuid)
    on conflict(id) do update set name = excluded.name, phalanx_id = excluded.phalanx_id;
    guide_ids := array_append(guide_ids,gid);
  end loop;
  if exists(select 1 from public.consultations where medium_id = v_id and not (guide_id = any(guide_ids))) then raise exception 'Não remova guias utilizados no histórico.'; end if;
  delete from public.guides where medium_id = v_id and not(id = any(guide_ids));
  return to_jsonb(r);
end $$;

create function public.set_medium_active(p_id uuid, p_active boolean, p_reason text default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.mediums;
begin
  perform app_private.require_admin();
  perform 1 from public.mediums where id = p_id for update;
  if not found then raise exception using errcode = 'CC404', message = 'Médium não encontrado.'; end if;
  if not p_active then
    if coalesce(btrim(p_reason),'') = '' then raise exception 'Informe o motivo da inativação.'; end if;
    if exists(select 1 from public.consultations where medium_id = p_id and status in ('waiting','queue','in_progress')) then raise exception 'Encerre ou remaneje as consultas pendentes.'; end if;
    if exists(select 1 from public.work_sessions where dirigent_id = p_id and work_day = app_private.work_day()) then raise exception 'Altere primeiro o dirigente da sessão.'; end if;
    update public.attendance set present = false, updated_at = now() where medium_id = p_id;
  end if;
  update public.mediums set active = p_active, inactive_reason = case when p_active then null else btrim(p_reason) end, inactivated_at = case when p_active then null else now() end, inactivated_by = case when p_active then null else auth.uid() end, updated_at = now() where id = p_id returning * into r;
  return to_jsonb(r);
end $$;

create function public.current_work_session(p_nucleo_id text) returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform app_private.require_access(p_nucleo_id,true);
  return (select to_jsonb(s) from public.work_sessions s where nucleo_id = p_nucleo_id and work_day = app_private.work_day());
end $$;
create function public.configure_session(p_data jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare n text := p_data->>'nucleo_id'; d uuid := (p_data->>'dirigent_id')::uuid; s public.work_sessions; ph uuid := (p_data->>'phalanx_id')::uuid;
begin
  perform app_private.require_access(n);
  -- Mesmo lock em todas as operações da sessão; evita alterações de falange concorrentes.
  perform pg_advisory_xact_lock(hashtextextended(n::text || app_private.work_day()::text,0));
  select * into s from public.work_sessions where nucleo_id = n and work_day = app_private.work_day() for update;
  if d is not null then
    perform 1 from public.mediums m join public.medium_nucleos mn on mn.medium_id = m.id where m.id = d and active and degree = 'dirigente' and mn.nucleo_id = n for update of m;
    if not found then raise exception 'Dirigente inválido para este núcleo.'; end if;
  end if;
  if s.id is not null then
    if s.locked_at is not null and s.phalanx_id <> ph then raise exception 'Falange travada após o primeiro atendimento.'; end if;
    if exists(select 1 from public.consultations where session_id = s.id and status = 'in_progress') and s.duration_minutes <> (p_data->>'duration_minutes')::integer then raise exception 'Há atendimentos em andamento; mantenha a duração.'; end if;
    if s.phalanx_id <> ph and exists(select 1 from public.consultations where session_id = s.id and status in ('waiting','queue')) then raise exception 'Remaneje a fila antes de alterar a falange.'; end if;
    update public.work_sessions set phalanx_id = ph, duration_minutes = (p_data->>'duration_minutes')::integer, consultation_limit = (p_data->>'consultation_limit')::integer, dirigent_id = d where id = s.id returning * into s;
  else
    insert into public.work_sessions(nucleo_id,work_day,phalanx_id,duration_minutes,consultation_limit,dirigent_id) values(n,app_private.work_day(),ph,(p_data->>'duration_minutes')::integer,(p_data->>'consultation_limit')::integer,d) returning * into s;
  end if;
  return to_jsonb(s);
end $$;

create function public.set_presence(p_session_id uuid,p_medium_id uuid,p_present boolean) returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.work_sessions; r public.attendance;
begin
  s := app_private.current_session(p_session_id);
  perform 1 from public.mediums where id = p_medium_id and active for update;
  if not found or not exists(select 1 from public.medium_nucleos where medium_id = p_medium_id and nucleo_id = s.nucleo_id) then raise exception 'Médium inválido para este núcleo.'; end if;
  -- Ausência não encerra uma consulta: apenas impede novos inícios e liberações futuras.
  insert into public.attendance(session_id,medium_id,present) values(p_session_id,p_medium_id,p_present)
  on conflict(session_id,medium_id) do update set present = excluded.present, updated_at = now() returning * into r;
  return to_jsonb(r);
end $$;

create function public.suggest_password(p_session_id uuid,p_password text) returns text language plpgsql security definer set search_path = '' as $$
declare s public.work_sessions; base text := regexp_replace(app_private.normalize_password(p_password),'[a-z]$',''); candidate text; i integer;
begin
  s := app_private.current_session(p_session_id);
  for i in 0..26 loop
    candidate := base || case when i = 0 then '' else chr(96+i) end;
    if not exists(select 1 from public.consultations where session_id = p_session_id and password = candidate) then return candidate; end if;
  end loop;
  raise exception 'Todas as variações desta senha estão ocupadas.';
end $$;

create function public.open_consultation(p_data jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.work_sessions; m uuid := (p_data->>'medium_id')::uuid; g uuid := (p_data->>'guide_id')::uuid; busy boolean; count_used integer; reason text := nullif(btrim(p_data->>'override_reason'),''); r public.consultations;
begin
  s := app_private.current_session((p_data->>'session_id')::uuid);
  perform app_private.check_medium(s,m,g);
  busy := exists(select 1 from public.consultations where medium_id = m and status = 'in_progress');
  if busy then
    select count(*) into count_used from public.consultations where medium_id = m and nucleo_id = s.nucleo_id and
      ((status = 'completed' and not is_test and (ended_at at time zone 'America/Sao_Paulo')::date = (now() at time zone 'America/Sao_Paulo')::date) or (session_id = s.id and status in ('waiting','queue')));
    if count_used >= s.consultation_limit and (reason is null or cardinality(regexp_split_to_array(reason,'\s+')) < 5) then raise exception 'Limite atingido: informe uma justificativa com pelo menos cinco palavras.'; end if;
  end if;
  insert into public.consultations(session_id,nucleo_id,medium_id,guide_id,password,consultant_name,status,started_at,duration_minutes,is_test,is_extra,override_reason,exceeded_by,medium_name,guide_name,phalanx_id,dirigent_id,dirigent_name,queued_at)
  values(s.id,s.nucleo_id,m,g,app_private.normalize_password(p_data->>'password'),btrim(p_data->>'consultant_name'),case when busy then 'waiting' else 'in_progress' end,case when busy then null else now() end,s.duration_minutes,
    coalesce((p_data->>'is_test')::boolean,false) or btrim(p_data->>'consultant_name') ~* '(^|[^a-zÀ-ÿ])teste([^a-zÀ-ÿ]|$)',
    busy and coalesce(count_used,0) >= s.consultation_limit,
    case when busy and count_used >= s.consultation_limit then reason else null end,
    case when busy and count_used >= s.consultation_limit then count_used + 1 - s.consultation_limit else 0 end,
    (select name from public.mediums where id = m),(select name from public.guides where id = g),s.phalanx_id,s.dirigent_id,(select name from public.mediums where id = s.dirigent_id),case when busy then now() else null end) returning * into r;
  if not busy then update public.work_sessions set locked_at = coalesce(locked_at,now()) where id = s.id; end if;
  return to_jsonb(r);
end $$;

create function public.start_consultation(p_id uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.consultations; s public.work_sessions;
begin
  -- Sessão antes da consulta: ordem de locks igual à criação/configuração.
  select * into r from public.consultations where id = p_id;
  if not found then raise exception using errcode = 'CC404',message = 'Consulta não encontrada.'; end if;
  s := app_private.current_session(r.session_id);
  select * into r from public.consultations where id = p_id for update;
  if r.status = 'in_progress' then return to_jsonb(r); end if;
  if r.status not in ('waiting','queue') then raise exception 'Consulta não está na fila.'; end if;
  perform app_private.check_medium(s,r.medium_id,r.guide_id);
  if exists(select 1 from public.consultations where medium_id = r.medium_id and status = 'in_progress') then raise exception 'Médium já está em atendimento.'; end if;
  update public.consultations set status = 'in_progress',started_at = now(),updated_at = now(),duration_minutes = s.duration_minutes,phalanx_id = s.phalanx_id,dirigent_id = s.dirigent_id,dirigent_name = (select name from public.mediums where id = s.dirigent_id) where id = p_id returning * into r;
  update public.work_sessions set locked_at = coalesce(locked_at,now()) where id = s.id;
  return to_jsonb(r);
end $$;

create function public.transfer_consultation(p_id uuid,p_medium_id uuid,p_guide_id uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.consultations; s public.work_sessions; busy boolean;
begin
  select * into r from public.consultations where id = p_id;
  if not found then raise exception using errcode = 'CC404',message = 'Consulta não encontrada.'; end if;
  s := app_private.current_session(r.session_id);
  select * into r from public.consultations where id = p_id for update;
  if r.status <> 'waiting' then raise exception 'Somente consultas em espera podem ser transferidas.'; end if;
  perform app_private.check_medium(s,p_medium_id,p_guide_id);
  busy := exists(select 1 from public.consultations where medium_id = p_medium_id and status = 'in_progress');
  update public.consultations set medium_id = p_medium_id,guide_id = p_guide_id,medium_name = (select name from public.mediums where id = p_medium_id),guide_name = (select name from public.guides where id = p_guide_id),status = case when busy then 'waiting' else 'in_progress' end,started_at = case when busy then null else now() end,updated_at = now(),duration_minutes = s.duration_minutes where id = p_id returning * into r;
  if not busy then update public.work_sessions set locked_at = coalesce(locked_at,now()) where id = s.id; end if;
  return to_jsonb(r);
end $$;

create function public.finish_consultation(p_id uuid,p_rating integer,p_feedback text default '') returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.consultations;
begin
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'Avalie de 1 a 5.'; end if;
  select * into r from public.consultations where id = p_id for update;
  if not found then raise exception using errcode = 'CC404',message = 'Consulta não encontrada.'; end if;
  perform app_private.require_access(r.nucleo_id,true);
  if r.status = 'completed' then return to_jsonb(r); end if;
  if r.status <> 'in_progress' then raise exception 'Consulta não está em andamento.'; end if;
  update public.consultations set status = 'completed',ended_at = now(),updated_at = now(),rating = p_rating,feedback = btrim(coalesce(p_feedback,'')),service_minutes = greatest(0,round(extract(epoch from (now()-started_at))/60)::integer) where id = p_id returning * into r;
  return to_jsonb(r);
end $$;

create function public.cancel_consultation(p_id uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.consultations;
begin
  select * into r from public.consultations where id = p_id for update;
  if not found then raise exception using errcode = 'CC404',message = 'Consulta não encontrada.'; end if;
  perform app_private.require_access(r.nucleo_id);
  if r.status = 'cancelled' then return to_jsonb(r); end if;
  if r.status = 'completed' then raise exception 'Consulta já concluída.'; end if;
  -- Preserva o histórico em vez de reproduzir a exclusão física do legado.
  update public.consultations set status = 'cancelled',ended_at = now(),updated_at = now(),service_minutes = case when started_at is null then null else greatest(0,round(extract(epoch from (now()-started_at))/60)::integer) end where id = p_id returning * into r;
  return to_jsonb(r);
end $$;

create function public.find_feedback_consultations(p_nucleo_id text,p_query text) returns setof public.consultations language plpgsql stable security definer set search_path = '' as $$
declare q text := btrim(p_query);
begin
  perform app_private.require_access(p_nucleo_id,true);
  if q is null or length(q) = 0 then return; end if;
  if q ~ '^[0-9]{1,4}[a-zA-Z]?$' then q := app_private.normalize_password(q); end if;
  return query select * from public.consultations where nucleo_id = p_nucleo_id and status = 'in_progress' and (password = lower(q) or position(lower(q) in lower(consultant_name)) > 0) order by created_at,id limit 50;
end $$;

-- Grants explícitos. SECURITY DEFINER exige validação de identidade e acesso em cada RPC.
revoke all on public.profiles,public.user_nucleos,public.consultation_nucleo_details,public.phalanxes,public.mediums,public.medium_nucleos,public.guides,public.work_sessions,public.attendance,public.consultations from anon, authenticated;
grant select on public.profiles,public.user_nucleos,public.consultation_nucleo_details,public.phalanxes,public.mediums,public.medium_nucleos,public.guides,public.work_sessions,public.attendance,public.consultations to authenticated;
revoke execute on all functions in schema app_private from public,anon,authenticated;
grant execute on function app_private.is_admin(),app_private.can_access(text) to authenticated;
revoke execute on function public.save_nucleo(jsonb),public.save_medium(jsonb),public.set_medium_active(uuid,boolean,text),public.current_work_session(text),public.configure_session(jsonb),public.set_presence(uuid,uuid,boolean),public.suggest_password(uuid,text),public.open_consultation(jsonb),public.start_consultation(uuid),public.transfer_consultation(uuid,uuid,uuid),public.finish_consultation(uuid,integer,text),public.cancel_consultation(uuid),public.find_feedback_consultations(text,text) from public,anon;
grant execute on function public.save_nucleo(jsonb),public.save_medium(jsonb),public.set_medium_active(uuid,boolean,text),public.current_work_session(text),public.configure_session(jsonb),public.set_presence(uuid,uuid,boolean),public.suggest_password(uuid,text),public.open_consultation(jsonb),public.start_consultation(uuid),public.transfer_consultation(uuid,uuid,uuid),public.finish_consultation(uuid,integer,text),public.cancel_consultation(uuid),public.find_feedback_consultations(text,text) to authenticated;

-- A assinatura de consultas serve à futura interface, respeitando RLS.
do $$ begin
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.consultations;
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
