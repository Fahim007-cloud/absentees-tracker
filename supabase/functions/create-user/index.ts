// supabase/functions/create-user/index.ts
//
// Handles creating and deleting Teacher/Representative/Admin accounts.
// This runs on Supabase's servers, never in the browser — it's the
// only place the service_role key is ever used, which is exactly why
// it has to live here instead of in index.html.
//
// Deploy with:
//   supabase functions deploy create-user
//
// SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY are
// injected automatically by Supabase — nothing to configure by hand.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'Missing authorization' }, 401)

    // Bound to the CALLER's own session — used only to find out who's asking.
    const callerClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user }, error: userError } = await callerClient.auth.getUser()
    if (userError || !user) return json({ error: 'Invalid session' }, 401)

    // Privileged client — service_role key never leaves this function.
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Only admins may call this function, for any action.
    const { data: callerProfile } = await admin
      .from('atrk_profiles')
      .select('role')
      .eq('id', user.id)
      .single()

    if (!callerProfile || callerProfile.role !== 'admin') {
      return json({ error: 'Only admins can manage users' }, 403)
    }

    const body = await req.json()

    if (body.action === 'create') {
      const { email, password, role } = body
      if (!email || !password || !role) return json({ error: 'Missing email, password, or role' }, 400)
      if (!['admin', 'teacher', 'representative'].includes(role)) return json({ error: 'Invalid role' }, 400)
      if (password.length < 6) return json({ error: 'Password must be at least 6 characters' }, 400)

      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
      })
      if (createError) return json({ error: createError.message }, 400)

      const { error: profileError } = await admin
        .from('atrk_profiles')
        .insert([{ id: created.user.id, email, role }])

      if (profileError) {
        // Don't leave an orphaned login with no role attached.
        await admin.auth.admin.deleteUser(created.user.id)
        return json({ error: profileError.message }, 400)
      }

      return json({ success: true, id: created.user.id })
    }

    if (body.action === 'delete') {
      const { userId } = body
      if (!userId) return json({ error: 'Missing userId' }, 400)
      if (userId === user.id) return json({ error: "You can't delete your own account" }, 400)

      await admin.from('atrk_profiles').delete().eq('id', userId)
      const { error: deleteError } = await admin.auth.admin.deleteUser(userId)
      if (deleteError) return json({ error: deleteError.message }, 400)

      return json({ success: true })
    }

    return json({ error: 'Unknown action' }, 400)
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : 'Unexpected error' }, 500)
  }
})
