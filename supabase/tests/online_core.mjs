// PostgreSQL embarcado para CI sem Docker. Não acessa o projeto remoto.
// npm install --prefix /tmp/centelha-pg-validation @electric-sql/pglite@0.5.10
// PGLITE_MODULE=/tmp/centelha-pg-validation/node_modules/@electric-sql/pglite/dist/index.js node supabase/tests/online_core.mjs
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const modulePath = process.env.PGLITE_MODULE;
if (!modulePath) throw new Error('Defina PGLITE_MODULE com o módulo temporário instalado.');
const { PGlite } = await import(pathToFileURL(modulePath));
const db = new PGlite();
const sharedRegistry = process.env.CENTELHA_EXISTING_REGISTRY === '1';
let sharedBefore;
async function sharedSnapshot() {
  return (await db.query("select jsonb_build_object('nucleos',(select jsonb_agg(n order by cod) from public.nucleos n),'usuarios',(select jsonb_agg(u order by id) from public.usuarios u),'consultas',(select jsonb_agg(c order by id) from public.consultas c),'notas',(select jsonb_agg(n order by id) from public.nota_consultas n),'policies',(select jsonb_agg(p order by policyname) from pg_policies p where schemaname='public' and tablename='nucleos'),'grants',(select jsonb_agg(g order by grantee,privilege_type) from information_schema.table_privileges g where table_schema='public' and table_name='nucleos'),'triggers',(select jsonb_agg(t order by tgname) from pg_trigger t where tgrelid='public.nucleos'::regclass and not tgisinternal)) as value")).rows[0].value;
}
let assertions = 0;
function check(actual, expected) { assert.deepEqual(actual, expected); assertions++; }
async function fails(operation, code) {
  try { await operation(); } catch (error) { if (code) assert.equal(error.code, code); assertions++; return; }
  assert.fail('A operação deveria falhar.');
}
const admin = '10000000-0000-0000-0000-000000000001';
const operator = '10000000-0000-0000-0000-000000000002';
const tablet = '10000000-0000-0000-0000-000000000003';
const outsider = '10000000-0000-0000-0000-000000000004';
const rpc = async (name, args) => (await db.query(`select public.${name}(${args.map((_, i) => '$' + (i + 1)).join(',')}) as result`, args)).rows[0].result;
async function login(id, role = 'authenticated') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id]);
  await db.query("select set_config('request.jwt.claim.role', $1, false)", [role]);
  await db.exec(`set role ${role}`);
}
try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key, raw_user_meta_data jsonb);
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
    grant usage on schema auth to public;
    create function auth.role() returns text language sql stable as $$ select current_setting('request.jwt.claim.role',true) $$;`);
  if (sharedRegistry) {
    await db.exec(await readFile(new URL('./fixtures/shared_registry.sql',import.meta.url),'utf8'));
    sharedBefore = await sharedSnapshot();
  }
  const migration = await readFile(new URL(sharedRegistry ? '../migrations/202610160002_existing_registry.sql' : '../bootstrap/202610160001_online_core.sql', import.meta.url), 'utf8');
  await db.exec(migration);
  if (sharedRegistry) check(await sharedSnapshot(),sharedBefore);
  for (const id of [admin, operator, tablet, outsider]) await db.query('insert into auth.users values($1,$2)', [id, {name: 'Fixture'}]);
  await db.query("update public.profiles set role = 'admin' where id = $1", [admin]);
  await db.query("update public.profiles set role = 'tablet' where id = $1", [tablet]);
  await login(admin);
  const n = await rpc('save_nucleo', [{name: 'Núcleo A',code: '002',abbreviation: 'NA'}]);
  const n2 = await rpc('save_nucleo', [{name: 'Núcleo B',code: '003',abbreviation: 'NB'}]);
  const phalanxes = (await db.query('select * from public.phalanxes order by position')).rows;
  check(phalanxes.length, 7);
  const draft = name => ({name, degree: 'dirigente', ribbon: 'green', nucleo_ids: [n.id, n2.id], guides: phalanxes.map((p, i) => ({name: 'Guia ' + i, phalanx_id: p.id}))});
  await fails(() => rpc('save_medium', [{...draft('Inválido'), nucleo_ids: []}]), 'P0001');
  await fails(() => rpc('save_medium', [{...draft('Inválido'), guides: []}]), 'P0001');
  const m = await rpc('save_medium', [draft('Médium A')]);
  const m2 = await rpc('save_medium', [draft('Médium B')]);
  await fails(() => rpc('save_medium', [draft('  MÉDIUM A ')]), '23505');
  const g = (await db.query('select * from public.guides where medium_id = $1 and phalanx_id = $2', [m.id, phalanxes[0].id])).rows[0];
  const g2 = (await db.query('select * from public.guides where medium_id = $1 and phalanx_id = $2', [m2.id, phalanxes[0].id])).rows[0];
  const wrong = (await db.query('select * from public.guides where medium_id = $1 and phalanx_id = $2', [m.id, phalanxes[1].id])).rows[0];
  await db.exec('reset role');
  for (const id of [operator, tablet]) await db.query('insert into public.user_nucleos values($1,$2)', [id,n.id]);
  await login(operator);
  check((await db.query('select * from public.list_consultation_nucleos()')).rows.map(r => r.id ?? r.list_consultation_nucleos.id), [n.id]);
  check((await db.query('select * from public.mediums')).rows.length, 2);
  await fails(() => rpc('save_nucleo', [{name: 'Não autorizado'}]), '42501');
  await fails(() => db.query("update public.profiles set role = 'admin' where id = $1", [operator]), '42501');
  if (!sharedRegistry) await fails(() => db.query("insert into public.nucleos(name) values('direto')"), '42501');
  await fails(() => rpc('current_work_session', [n2.id]), '42501');
  const config = {nucleo_id: n.id, phalanx_id: phalanxes[0].id, duration_minutes: 30, consultation_limit: 3, dirigent_id: m.id};
  await fails(() => rpc('configure_session', [{...config, duration_minutes: 29}]), '23514');
  await fails(() => rpc('configure_session', [{...config, consultation_limit: 2}]), '23514');
  const s = await rpc('configure_session', [config]);
  const open = password => ({session_id: s.id, medium_id: m.id, guide_id: g.id, password, consultant_name: 'Pessoa'});
  await fails(() => rpc('open_consultation', [open('001')]), 'P0001');
  await rpc('set_presence', [s.id,m.id,true]);
  await rpc('set_presence', [s.id,m2.id,true]);
  await fails(() => rpc('open_consultation', [{...open('001'), guide_id: wrong.id}]), 'P0001');
  const first = await rpc('open_consultation', [open('001')]);
  check(first.password, '1'); check(first.status, 'in_progress');
  if (sharedRegistry) { check(first.nucleo_id,'002'); check(first.dirigent_name,'Médium A'); }
  await fails(() => rpc('open_consultation', [open('0001')]), '23505');
  check(await rpc('suggest_password', [s.id,'0001']), '1a');
  const waiting = await rpc('open_consultation', [open('1a')]);
  check(waiting.status, 'waiting');
  if (sharedRegistry) check(typeof waiting.queued_at,'string');
  await rpc('open_consultation', [open('2')]);
  await rpc('open_consultation', [open('3')]);
  await fails(() => rpc('open_consultation', [open('4')]), 'P0001');
  await fails(() => rpc('open_consultation', [{...open('4'),override_reason: 'Curto demais'}]), 'P0001');
  const extra = await rpc('open_consultation', [{...open('4'),override_reason: 'Este atendimento extra foi autorizado hoje'}]);
  check(extra.is_extra,true); check(extra.exceeded_by,1);
  await fails(() => rpc('configure_session', [{...config,phalanx_id: phalanxes[1].id}]), 'P0001');
  await fails(() => rpc('start_consultation', [waiting.id]), 'P0001');
  await login(admin);
  // Outro núcleo continua respeitando a ocupação global do médium.
  const other = await rpc('configure_session', [{...config,nucleo_id: n2.id}]);
  await rpc('set_presence', [other.id,m.id,true]);
  const cross = await rpc('open_consultation', [{...open('1'),session_id: other.id}]);
  check(cross.status,'waiting');
  await fails(() => rpc('start_consultation', [cross.id]), 'P0001');
  await fails(() => rpc('set_medium_active', [m.id,false,'Afastado']), 'P0001');
  // Falha de edição não deixa vínculos/guia parcialmente gravados.
  await fails(() => rpc('save_medium', [{...draft('Médium editado'),id:m.id}]), 'P0001');
  check((await db.query('select name from public.mediums where id=$1',[m.id])).rows[0].name,'Médium A');
  await login(tablet);
  check((await db.query('select * from public.consultations')).rows.length,1);
  check((await db.query('select * from public.mediums')).rows.length,2);
  check((await db.query('select * from public.find_feedback_consultations($1,$2)',[n.id,'0001'])).rows.length,1);
  await fails(() => rpc('cancel_consultation', [first.id]), '42501');
  await fails(() => rpc('open_consultation', [open('5')]), '42501');
  await fails(() => rpc('finish_consultation', [first.id,0,'']), 'P0001');
  const completed = await rpc('finish_consultation', [first.id,5,'Bom']);
  check(completed.status,'completed'); check(completed.service_minutes,0);
  check((await rpc('finish_consultation', [first.id,1,'Reenvio'])).feedback,'Bom');
  check((await db.query('select * from public.consultations')).rows.length,0);
  await login(operator);
  const moved = await rpc('transfer_consultation', [waiting.id,m2.id,g2.id]);
  check(moved.status,'in_progress'); check(moved.medium_id,m2.id);
  await fails(() => rpc('transfer_consultation', [waiting.id,m.id,g.id]), 'P0001');
  const cancelled = await rpc('cancel_consultation', [waiting.id]);
  check(cancelled.status,'cancelled');
  check((await rpc('cancel_consultation', [waiting.id])).status,'cancelled');
  await fails(() => rpc('start_consultation', [waiting.id]), 'P0001');
  await fails(() => rpc('cancel_consultation', [first.id]), 'P0001');
  await login(outsider);
  check((await db.query('select * from public.list_consultation_nucleos()')).rows.length,0);
  check((await db.query('select * from public.consultations')).rows.length,0);
  await fails(() => rpc('finish_consultation', [first.id,5,'']), '42501');
  await login('', 'anon');
  await fails(() => db.query('select * from public.phalanxes'), '42501');
  await fails(() => rpc('finish_consultation', [first.id,5,'']), '42501');
  if (sharedRegistry) {
    await db.exec('reset role');
    const after = await sharedSnapshot();
    check({...after,nucleos:after.nucleos.filter(n => n.cod === '001')},sharedBefore);
    await login(admin);
    await fails(() => rpc('save_nucleo',[{name:'Sem código'}]),'P0001');
    const edited = await rpc('save_nucleo',[{id:'002',name:'Núcleo A editado',description:'Descrição do módulo'}]);
    check(edited.id,'002'); check(edited.abbreviation,'NA'); check(edited.description,'Descrição do módulo');
    await fails(() => rpc('save_nucleo',[{id:'002',code:'OUTRO',name:'Mudou'}]),'P0001');
    await db.exec('reset role');
    const countBefore = (await db.query('select count(*)::int as n from public.consultations')).rows[0].n;
    await fails(() => db.exec(migration),'P0001');
    await db.exec('rollback');
    check((await db.query('select count(*)::int as n from public.consultations')).rows[0].n,countBefore);
  }
  console.log(`PostgreSQL (${sharedRegistry ? 'cadastro compartilhado' : 'base nova'}): migração aplicada e ${assertions} verificações passaram (regras, rollback e permissões).`);
} finally { await db.close(); }
