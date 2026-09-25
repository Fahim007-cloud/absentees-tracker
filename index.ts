import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.117.2'

const allowedOrigins = (Deno.env.get('APP_ORIGINS') || 'https://absentcse.netlify.app')
  .split(',')
  .map(origin => origin.trim())
  .filter(Boolean)

const baseCorsHeaders = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const roles = ['admin', 'teacher', 'representative']

function originAllowed(origin) {
  return !origin || allowedOrigins.includes(origin)
}

function corsHeaders(origin) {
  return origin
    ? { ...baseCorsHeaders, 'Access-Control-Allow-Origin': origin }
    : baseCorsHeaders
}

function json(body, status = 200, origin = '') {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json',
    },
  })
}

function publicError(error, fallback) {
  const message = error instanceof Error ? error.message : ''
  if (/already (registered|exists)|already been registered/i.test(message)) {
    return 'An account with that email already exists'
  }
  return fallback
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin') || ''

  if (!originAllowed(origin)) {
    return new Response('Forbidden', { status: 403, headers: { Vary: 'Origin' } })
  }

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(origin) })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405, origin)
  }

  try {
    const contentType = req.headers.get('Content-Type') || ''
    if (!contentType.toLowerCase().startsWith('application/json')) {
      return json({ error: 'Content-Type must be application/json' }, 415, origin)
    }

    const rawBody = await req.text()
    if (rawBody.length > 16_384) {
      return json({ error: 'Request body is too large' }, 413, origin)
    }

    let body
    try {
      body = JSON.parse(rawBody)
    } catch {
      return json({ error: 'Invalid JSON' }, 400, origin)
    }

    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return json({ error: 'Invalid request' }, 400, origin)
    }

    const authHeader = req.headers.get('Authorization') || ''
    if (!authHeader.startsWith('Bearer ')) {
      return json({ error: 'Missing authorization' }, 401, origin)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return json({ error: 'Function is not configured' }, 500, origin)
    }

    const callerClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: userError } = await callerClient.auth.getUser()
    if (userError || !user) {
      return json({ error: 'Invalid session' }, 401, origin)
    }

    const admin = createClient(supabaseUrl, serviceRoleKey)
    const { data: callerProfile, error: profileLookupError } = await admin
      .from('atrk_profiles')
      .select('role')
      .eq('id', user.id)
      .single()

    if (profileLookupError || !callerProfile || callerProfile.role !== 'admin') {
      return json({ error: 'Only admins can manage users' }, 403, origin)
    }

    if (body.action === 'create') {
      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''
      const password = typeof body.password === 'string' ? body.password : ''
      const role = body.role

      if (!emailPattern.test(email) || email.length > 320) {
        return json({ error: 'Enter a valid email address' }, 400, origin)
      }
      if (password.length < 12 || password.length > 128) {
        return json({ error: 'Password must be between 12 and 128 characters' }, 400, origin)
      }
      if (typeof role !== 'string' || !roles.includes(role)) {
        return json({ error: 'Invalid role' }, 400, origin)
      }

      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      })
      if (createError || !created.user) {
        return json({ error: publicError(createError, 'Could not create user') }, 400, origin)
      }

      const { error: profileError } = await admin
        .from('atrk_profiles')
        .insert([{ id: created.user.id, email, role }])

      if (profileError) {
        await admin.auth.admin.deleteUser(created.user.id)
        return json({ error: 'Could not create user profile' }, 400, origin)
      }

      return json({ success: true, id: created.user.id }, 200, origin)
    }

    if (body.action === 'delete') {
      const userId = typeof body.userId === 'string' ? body.userId : ''
      if (!uuidPattern.test(userId)) {
        return json({ error: 'Invalid user ID' }, 400, origin)
      }
      if (userId === user.id) {
        return json({ error: "You can't delete your own account" }, 400, origin)
      }

      const { error: deleteError } = await admin.auth.admin.deleteUser(userId)
      if (deleteError) {
        return json({ error: 'Could not delete user' }, 400, origin)
      }

      return json({ success: true }, 200, origin)
    }

    if (body.action === 'reset_password') {
      const userId = typeof body.userId === 'string' ? body.userId : ''
      const newPassword = typeof body.newPassword === 'string' ? body.newPassword : ''
      if (!uuidPattern.test(userId)) {
        return json({ error: 'Invalid user ID' }, 400, origin)
      }
      if (newPassword.length < 12 || newPassword.length > 128) {
        return json({ error: 'Password must be between 12 and 128 characters' }, 400, origin)
      }

      const { error: resetError } = await admin.auth.admin.updateUserById(userId, {
        password: newPassword,
      })
      if (resetError) {
        return json({ error: 'Could not reset password' }, 400, origin)
      }

      return json({ success: true }, 200, origin)
    }

    return json({ error: 'Unknown action' }, 400, origin)
  } catch {
    return json({ error: 'Unexpected error' }, 500, origin)
  }
})
