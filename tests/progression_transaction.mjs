// Exact migration on an in-memory PostgreSQL runtime; never connects to Supabase.
// PGLITE_MODULE points to a dependency installed OUTSIDE the repository.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE);
const db = new PGlite();
const pid='00000000-0000-0000-0000-000000000001', other='00000000-0000-0000-0000-000000000002';
await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE TABLE exercises(id uuid PRIMARY KEY,name text UNIQUE,current_weight numeric,default_scheme text,deleted_at timestamptz);
CREATE TABLE user_profile(id int PRIMARY KEY,active_program_id uuid);
CREATE TABLE program_sessions(id uuid PRIMARY KEY,program_id uuid,name text);
CREATE TABLE program_blocks(id uuid PRIMARY KEY,session_id uuid REFERENCES program_sessions(id));
CREATE TABLE program_block_exercises(id uuid PRIMARY KEY,block_id uuid REFERENCES program_blocks(id),exercise_id uuid REFERENCES exercises(id),scheme text);
INSERT INTO user_profile VALUES(1,'${pid}');
INSERT INTO exercises VALUES('${pid}','X',100,'3x12',NULL);
INSERT INTO program_sessions VALUES('${pid}','${pid}','A'),('${other}','${other}','A');
INSERT INTO program_blocks VALUES('${pid}','${pid}'),('${other}','${other}');
INSERT INTO program_block_exercises VALUES('${pid}','${pid}','${pid}','3x12'),('${other}','${other}','${pid}','5x5');
`);
await db.exec(readFileSync(new URL('../docs/migrations/096_progression_coaching.sql',import.meta.url),'utf8'));
const base={exercise_name:'X',suggested_weight:105,suggested_scheme:'4x12',expected_current_weight:100,expected_current_scheme:'3x12',session_date:'2026-10-02',session_type:'evening',session_name:'A',program_id:pid};
const apply=async changes=>(await db.query('SELECT apply_progression($1::jsonb) AS result',[JSON.stringify({...base,...changes})])).rows[0].result;
const state=async()=>(await db.query(`SELECT e.current_weight::float8 AS weight,e.default_scheme AS scheme,pe.scheme AS program_scheme FROM exercises e JOIN program_block_exercises pe ON pe.exercise_id=e.id WHERE pe.id='${pid}'`)).rows[0];
const reset=()=>db.exec(`UPDATE exercises SET current_weight=100,default_scheme='3x12',progression_reference=false,progression_schemes='{}'; UPDATE program_block_exercises SET scheme='3x12' WHERE id='${pid}';`);
let count=0;
async function test(name,body){await reset();await body();count++;console.log('PASS '+name)}
await test('weight only',async()=>{assert.equal((await apply({suggested_scheme:null})).success,true);assert.deepEqual(await state(),{weight:105,scheme:'3x12',program_scheme:'3x12'})});
await test('scheme only',async()=>{assert.equal((await apply({suggested_weight:null})).success,true);assert.deepEqual(await state(),{weight:100,scheme:'4x12',program_scheme:'4x12'})});
await test('both and programme isolation',async()=>{assert.equal((await apply()).success,true);assert.deepEqual(await state(),{weight:105,scheme:'4x12',program_scheme:'4x12'});assert.equal((await db.query(`SELECT scheme FROM program_block_exercises WHERE id='${other}'`)).rows[0].scheme,'5x5')});
await test('stale weight',async()=>{await db.exec('UPDATE exercises SET current_weight=110');assert.equal((await apply()).status,409);assert.equal((await state()).weight,110)});
await test('stale scheme',async()=>{await db.exec("UPDATE exercises SET default_scheme='5x12'");assert.equal((await apply()).status,409);assert.equal((await state()).program_scheme,'3x12')});
await test('programme independently edited',async()=>{await db.exec(`UPDATE program_block_exercises SET scheme='2x12' WHERE id='${pid}'`);assert.equal((await apply()).status,409);assert.equal((await state()).weight,100)});
await test('missing exercise',async()=>assert.equal((await apply({exercise_name:'missing'})).status,404));
await test('missing prescription',async()=>assert.equal((await apply({session_name:'missing'})).status,409));
await test('changed active programme',async()=>{await db.exec(`UPDATE user_profile SET active_program_id='${other}'`);assert.equal((await apply()).status,409);await db.exec(`UPDATE user_profile SET active_program_id='${pid}'`)});
await test('controlled retry',async()=>{assert.equal((await apply()).success,true);assert.equal((await apply()).status,409)});
await test('undo both and stale undo',async()=>{await apply();const undo={suggested_weight:100,suggested_scheme:'3x12',expected_current_weight:105,expected_current_scheme:'4x12',restore:true};assert.equal((await apply(undo)).success,true);assert.deepEqual(await state(),{weight:100,scheme:'3x12',program_scheme:'3x12'});assert.equal((await apply(undo)).status,409)});
await test('undo nullable original weight',async()=>{await db.exec('UPDATE exercises SET current_weight=NULL');assert.equal((await apply({expected_current_weight:null})).success,true);assert.equal((await apply({suggested_weight:null,suggested_scheme:'3x12',expected_current_weight:105,expected_current_scheme:'4x12',restore:true})).success,true);assert.equal((await state()).weight,null)});
await test('programme write failure rolls back exercise write',async()=>{
 await db.exec(`CREATE FUNCTION reject_program() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture second write failure'; END $$; CREATE TRIGGER reject_program BEFORE UPDATE ON program_block_exercises FOR EACH ROW EXECUTE FUNCTION reject_program();`);
 await assert.rejects(()=>apply(),/fixture second write failure/);assert.deepEqual(await state(),{weight:100,scheme:'3x12',program_scheme:'3x12'});
 await db.exec('DROP TRIGGER reject_program ON program_block_exercises;DROP FUNCTION reject_program();');
});
await test('exercise failure leaves programme unchanged',async()=>{
 await db.exec(`CREATE FUNCTION reject_exercise() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture first write failure'; END $$; CREATE TRIGGER reject_exercise BEFORE UPDATE ON exercises FOR EACH ROW EXECUTE FUNCTION reject_exercise();`);
 await assert.rejects(()=>apply(),/fixture first write failure/);assert.deepEqual(await state(),{weight:100,scheme:'3x12',program_scheme:'3x12'});
 await db.exec('DROP TRIGGER reject_exercise ON exercises;DROP FUNCTION reject_exercise();');
});
await test('direct client RPC denied',async()=>{const r=await db.query("SELECT has_function_privilege('anon','apply_progression(jsonb)','execute') a,has_function_privilege('authenticated','apply_progression(jsonb)','execute') b,has_function_privilege('service_role','apply_progression(jsonb)','execute') c");assert.deepEqual(r.rows[0],{a:false,b:false,c:true})});
console.log(`SQL_RESULT ${count} passed (single-connection PostgreSQL; no live account)`);
await db.close();
