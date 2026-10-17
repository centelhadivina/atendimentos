import assert from 'node:assert/strict';
import { createQuickAccessHandler } from '../functions/_shared/quick_access.mjs';
let calls=[];
const make=(options={})=>createQuickAccessHandler({url:'https://example.test',publishableKey:'public-test-key',getSecret:()=> 'synthetic-secret',fetchImpl:async(url,init)=>{
 calls.push({url,init});
 if(url.includes('/auth/')) return Response.json({access_token:'synthetic-access',refresh_token:'synthetic-refresh',user:{email:'tecnologia.ccu@gmail.com'}});
 return Response.json({role:'tablet',user_nucleos:[{nucleo_id:'001'}]});
},...options});
const request=body=>new Request('https://example.test/quick-access',{method:'POST',body:JSON.stringify(body),headers:{'Content-Type':'application/json'}});
let response=await make()(request({nucleo_id:'001',role:'tablet'}));
assert.equal(response.status,200);assert.deepEqual(await response.json(),{refresh_token:'synthetic-refresh'});
assert.equal(calls.length,2);assert.equal(JSON.parse(calls[0].init.body).email,'tecnologia.ccu@gmail.com');
assert.equal(response.headers.get('cache-control'),'no-store');
for(const body of [{nucleo_id:'001',role:'admin'},{nucleo_id:'999',role:'tablet'},{nucleo_id:'001',role:'tablet',email:'someone@example.com'}]) {
 calls=[];response=await make()(request(body));assert.equal(response.status,400);assert.equal(calls.length,0);
}
response=await make({getSecret:()=>undefined})(request({nucleo_id:'001',role:'tablet'}));assert.equal(response.status,503);
response=await make({fetchImpl:async()=>Response.json({error:'never expose internal details'},{status:401})})(request({nucleo_id:'001',role:'tablet'}));assert.equal(response.status,401);assert.equal((await response.text()).includes('internal'),false);
response=await make({fetchImpl:async()=>{throw new Error('sensitive');}})(request({nucleo_id:'001',role:'tablet'}));assert.equal(response.status,503);
let n=0;response=await make({fetchImpl:async()=> ++n===1 ? Response.json({access_token:'x',refresh_token:'y',user:{email:'tecnologia.ccu@gmail.com'}}) : Response.json({role:'admin',user_nucleos:[{nucleo_id:'001'}]})})(request({nucleo_id:'001',role:'tablet'}));assert.equal(response.status,403);
response=await make()(new Request('https://example.test',{method:'OPTIONS'}));assert.equal(response.status,204);
console.log('Acesso rápido: allowlist, autorização, sessão, CORS e falhas sem exposição de senhas validados.');
