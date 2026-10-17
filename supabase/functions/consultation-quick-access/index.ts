import { createQuickAccessHandler } from '../_shared/quick_access.mjs';
Deno.serve(createQuickAccessHandler({
  url: Deno.env.get('SUPABASE_URL'),
  publishableKey: Deno.env.get('CONSULTAS_PUBLISHABLE_KEY') ?? Deno.env.get('SUPABASE_ANON_KEY'),
  getSecret: (name: string) => Deno.env.get(name),
}));
