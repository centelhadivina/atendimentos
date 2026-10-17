-- Estrutura relevante do diagnóstico fornecido; contém somente dados sintéticos.
create table public.nucleos (
  cod varchar primary key, sigla varchar not null unique, nome varchar not null,
  coordenador varchar, ativo boolean default true,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create function public.atualizar_timestamp_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
create trigger atualizar_nucleos_updated_at before update on public.nucleos for each row execute function public.atualizar_timestamp_updated_at();
alter table public.nucleos enable row level security;
create policy "Leitura pública de núcleos" on public.nucleos for select to public using(true);
create policy "Escrita autenticada de núcleos" on public.nucleos for all to public using(auth.role() = 'authenticated');
grant select on public.nucleos to anon;
grant select,insert,update,delete on public.nucleos to authenticated;
insert into public.nucleos(cod,sigla,nome,coordenador) values('001','LEG','Núcleo compartilhado','Coordenação existente');
create table public.usuarios(id uuid primary key default gen_random_uuid(), numero_cadastro varchar not null unique, nome varchar not null, cpf varchar not null unique);
create table public.consultas(id uuid primary key default gen_random_uuid(), numero_consulta varchar not null unique, cadastro_consulente varchar references public.usuarios(numero_cadastro), data_consulta timestamptz not null);
create table public.nota_consultas(id uuid primary key default gen_random_uuid(), membro_id text not null, nome text not null, nome_guia text not null, nota numeric not null check(nota between 0 and 10), data date not null);
insert into public.usuarios(numero_cadastro,nome,cpf) values('TEST-001','Pessoa sintética','CPF-SINTETICO');
insert into public.consultas(numero_consulta,cadastro_consulente,data_consulta) values('LEG-001','TEST-001','2026-10-16T20:00:00Z');
insert into public.nota_consultas(membro_id,nome,nome_guia,nota,data) values('TEST-001','Pessoa sintética','Guia sintético',9.5,'2026-10-16');
