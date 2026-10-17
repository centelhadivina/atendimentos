-- Somente metadados: não altera o banco nem consulta registros de usuários/consultas.
-- Execute no SQL Editor e copie o JSON retornado para ajustar a migração existente.
select jsonb_pretty(jsonb_build_object(
  'tables', coalesce((
    select jsonb_agg(jsonb_build_object(
      'schema', t.table_schema, 'name', t.table_name, 'type', t.table_type,
      'columns', coalesce((select jsonb_agg(jsonb_build_object(
        'name', c.column_name, 'type', c.udt_name, 'nullable', c.is_nullable,
        'default', c.column_default, 'identity', c.is_identity
      ) order by c.ordinal_position) from information_schema.columns c
        where c.table_schema = t.table_schema and c.table_name = t.table_name), '[]'::jsonb),
      'constraints', coalesce((select jsonb_agg(jsonb_build_object(
        'name', con.conname, 'type', con.contype, 'definition', pg_get_constraintdef(con.oid)
      ) order by con.conname) from pg_constraint con
        join pg_class rel on rel.oid = con.conrelid join pg_namespace ns on ns.oid = rel.relnamespace
        where ns.nspname = t.table_schema and rel.relname = t.table_name), '[]'::jsonb)
    ) order by t.table_schema,t.table_name)
    from information_schema.tables t
    where t.table_schema in ('public','app_private')
  ), '[]'::jsonb),
  'policies', coalesce((select jsonb_agg(jsonb_build_object(
    'schema', schemaname, 'table', tablename, 'name', policyname,
    'command', cmd, 'roles', roles, 'using', qual, 'check', with_check
  ) order by schemaname,tablename,policyname) from pg_policies where schemaname in ('public','app_private')), '[]'::jsonb),
  'indexes', coalesce((select jsonb_agg(jsonb_build_object(
    'schema', schemaname, 'table', tablename, 'name', indexname, 'definition', indexdef
  ) order by schemaname,tablename,indexname) from pg_indexes where schemaname in ('public','app_private')), '[]'::jsonb),
  'functions', coalesce((select jsonb_agg(jsonb_build_object(
    'schema', n.nspname, 'name', p.proname, 'arguments', pg_get_function_identity_arguments(p.oid),
    'result', pg_get_function_result(p.oid)
  ) order by n.nspname,p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_private' or (n.nspname = 'public' and p.proname in (
      'save_nucleo','save_medium','set_medium_active','current_work_session','configure_session',
      'set_presence','suggest_password','open_consultation','start_consultation','transfer_consultation',
      'finish_consultation','cancel_consultation','find_feedback_consultations'
    ))), '[]'::jsonb),
  'triggers', coalesce((select jsonb_agg(jsonb_build_object(
    'schema', ns.nspname, 'table', rel.relname, 'name', tr.tgname,
    'definition', pg_get_triggerdef(tr.oid)
  ) order by ns.nspname,rel.relname,tr.tgname)
    from pg_trigger tr join pg_class rel on rel.oid = tr.tgrelid join pg_namespace ns on ns.oid = rel.relnamespace
    where not tr.tgisinternal and (ns.nspname in ('public','app_private') or (ns.nspname = 'auth' and rel.relname = 'users'))), '[]'::jsonb)
)) as schema_diagnostic;
