// Run with PGLITE_MODULE=/isolated/node_modules/@electric-sql/pglite/dist/index.js node this-file.
// PGlite runs PostgreSQL in WASM, in memory, with no production connection.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite} = await import(process.env.PGLITE_MODULE);
const sql = await readFile(new URL('../docs/migrations/097_day_composer_occurrence_identity.sql', import.meta.url), 'utf8');
const schema = `CREATE TABLE public.exercise_logs (
 session_id text, exercise_id text, side text NOT NULL DEFAULT 'both', weight numeric,
 CONSTRAINT exercise_logs_session_id_exercise_id_side_key UNIQUE(session_id,exercise_id,side));`;
const db = new PGlite();
await db.exec(schema);
await db.exec("INSERT INTO exercise_logs VALUES ('user-a-session', 'curl', 'both', 10)");
await db.exec(sql);
assert.equal((await db.query('SELECT occurrence_key FROM exercise_logs')).rows[0].occurrence_key, '');
async function put(session, side, key, weight) {
 await db.query(`INSERT INTO exercise_logs(session_id,exercise_id,side,occurrence_key,weight)
 VALUES ($1,'curl',$2,$3,$4) ON CONFLICT(session_id,exercise_id,side,occurrence_key)
 DO UPDATE SET weight=excluded.weight`, [session,side,key,weight]);
}
await put('user-a-session','both','',11);
assert.equal((await db.query('SELECT count(*)::int AS n FROM exercise_logs')).rows[0].n,1);
await put('user-a-session','both','A',20); await put('user-a-session','both','B',30);
await put('user-a-session','both','A',21); await put('user-a-session','left','A',40);
await put('user-b-session','both','A',50);
const rows=(await db.query('SELECT * FROM exercise_logs ORDER BY session_id,side,occurrence_key')).rows;
assert.equal(rows.length,5);
assert.equal(rows.find(r=>r.occurrence_key==='A' && r.side==='both' && r.session_id==='user-a-session').weight, '21');
assert.equal(rows.find(r=>r.occurrence_key==='B').weight, '30');
assert.equal(rows.find(r=>r.session_id==='user-b-session').weight, '50');
await assert.rejects(()=>put('user-a-session','both','x'.repeat(161),1));
await db.close();
// Force a mid-migration DDL failure: transaction must remove the newly added column too.
const rollback = new PGlite(); await rollback.exec(schema);
await rollback.exec('ALTER TABLE exercise_logs DROP CONSTRAINT exercise_logs_session_id_exercise_id_side_key');
await assert.rejects(()=>rollback.exec(sql)); await rollback.exec('ROLLBACK');
assert.equal((await rollback.query("SELECT count(*)::int AS n FROM information_schema.columns WHERE table_name='exercise_logs' AND column_name='occurrence_key'")).rows[0].n,0);
await rollback.close();
console.log('PASS migration 097: legacy default/upsert, A/B/re-upsert, side/session isolation, length, atomic rollback');
