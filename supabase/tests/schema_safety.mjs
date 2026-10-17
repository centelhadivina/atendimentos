import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
if (!process.env.PGLITE_MODULE) throw new Error('Defina PGLITE_MODULE.');
const { PGlite } = await import(pathToFileURL(process.env.PGLITE_MODULE));
const db = new PGlite();
try {
  // Simula uma estrutura existente incompatível (IDs legados em texto).
  await db.exec(`create table public.nucleos(id text primary key, name text, description text);
    insert into public.nucleos values('0001','Núcleo preservado','Não modificar');`);
  const migration = await readFile(new URL('../bootstrap/202610160001_online_core.sql',import.meta.url),'utf8');
  await assert.rejects(() => db.exec(migration), error => error.code === 'P0001' && error.message.includes('public.nucleos'));
  await db.exec('rollback');
  assert.deepEqual((await db.query('select * from public.nucleos')).rows,[{id:'0001',name:'Núcleo preservado',description:'Não modificar'}]);
  assert.equal((await db.query("select to_regclass('public.profiles') as object")).rows[0].object,null);
  assert.equal((await db.query("select count(*)::int as n from pg_namespace where nspname = 'app_private'")).rows[0].n,0);
  const diagnostic = await readFile(new URL('../diagnostics/existing_schema.sql',import.meta.url),'utf8');
  const result = JSON.parse((await db.query(diagnostic)).rows[0].schema_diagnostic);
  assert.deepEqual(result.tables[0].columns.map(c => [c.name,c.type]),[['id','text'],['name','text'],['description','text']]);
  assert.equal(result.tables[0].constraints.some(c => c.type === 'p'),true);
  assert.equal(JSON.stringify(result).includes('Núcleo preservado'),false);
  assert.deepEqual((await db.query('select name from public.nucleos')).rows,[{name:'Núcleo preservado'}]);
  console.log('Schema: conflito detectado antes de alterações; dados preservados; diagnóstico validado sem registros.');
} finally { await db.close(); }
