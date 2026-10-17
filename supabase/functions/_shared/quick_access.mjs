// Handler independente de Deno, testável sem rede nem credenciais reais.
const accounts = Object.freeze({
  '001:cambono': {email:'ccu.acentelhadivina@gmail.com',secret:'CONSULTAS_CCU_PASSWORD'},
  '001:tablet': {email:'tecnologia.ccu@gmail.com',secret:'CONSULTAS_CCU_PASSWORD'},
  '002:cambono': {email:'cpo.acentelhadivina@gmail.com',secret:'CONSULTAS_CPO_PASSWORD'},
  '002:tablet': {email:'tecnologia.cpo@outlook.com',secret:'CONSULTAS_CPO_PASSWORD'},
});
const headers = {'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply = (status,error) => new Response(JSON.stringify(error),{status,headers});
export function createQuickAccessHandler({url,publishableKey,getSecret,fetchImpl=fetch}) {
  return async request => {
    if (request.method==='OPTIONS') return new Response(null,{status:204,headers});
    if (request.method!=='POST') return reply(405,{error:'Método não permitido.'});
    try {
      const body = await request.json();
      if (!body || typeof body!=='object' || Array.isArray(body) || typeof body.nucleo_id!=='string' || typeof body.role!=='string' || Object.keys(body).some(k => !['nucleo_id','role'].includes(k))) return reply(400,{error:'Dados de acesso inválidos.'});
      const account = accounts[`${body.nucleo_id}:${body.role}`];
      if (!account) return reply(400,{error:'Escolha núcleo e perfil de acesso rápido válidos.'});
      const password = getSecret(account.secret);
      if (!url || !publishableKey || !password) return reply(503,{error:'Acesso rápido ainda não configurado.'});
      const tokenResponse = await fetchImpl(`${url}/auth/v1/token?grant_type=password`,{
        method:'POST', headers:{'apikey':publishableKey,'Content-Type':'application/json'},
        body:JSON.stringify({email:account.email,password}), signal:AbortSignal.timeout(15000),
      });
      if (!tokenResponse.ok) return reply(401,{error:'Não foi possível autenticar o acesso rápido.'});
      const session = await tokenResponse.json();
      if (!session.access_token || !session.refresh_token || session.user?.email?.toLowerCase()!==account.email) return reply(401,{error:'Sessão inválida.'});
      const profileResponse = await fetchImpl(`${url}/rest/v1/rpc/my_consultation_profile`,{
        method:'POST',headers:{'apikey':publishableKey,'Authorization':`Bearer ${session.access_token}`,'Content-Type':'application/json'},
        body:'{}',signal:AbortSignal.timeout(15000),
      });
      if (!profileResponse.ok) return reply(403,{error:'Conta sem autorização para este acesso.'});
      const profile = await profileResponse.json();
      if (profile.role!==body.role || !profile.user_nucleos?.some(n => n.nucleo_id===body.nucleo_id)) return reply(403,{error:'Conta sem autorização para este núcleo e perfil.'});
      // O cliente troca o refresh_token por sua própria sessão persistida no SDK.
      return reply(200,{refresh_token:session.refresh_token});
    } catch { return reply(503,{error:'Serviço de acesso rápido indisponível.'}); }
  };
}
