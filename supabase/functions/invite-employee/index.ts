const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const allowedRoles = new Set(['system_administrator', 'factory_manager', 'planning_manager', 'department_manager', 'department_employee', 'qa_approver', 'dispatch_officer', 'management_viewer'])
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const adminHeaders = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}`, 'Content-Type': 'application/json' }

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405)
  if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Supabase server secrets are not configured' }, 500)
  const token = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token) return json({ error: 'Authentication is required' }, 401)

  const callerResponse = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey: serviceRoleKey, Authorization: `Bearer ${token}` } })
  if (!callerResponse.ok) return json({ error: 'Invalid session' }, 401)
  const caller = await callerResponse.json() as { id?: string }
  const roleResponse = await fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${caller.id}&select=role,is_active`, { headers: adminHeaders })
  const callerProfile = (await roleResponse.json())[0] as { role?: string; is_active?: boolean } | undefined
  if (callerProfile?.role !== 'system_administrator' || !callerProfile.is_active) return json({ error: 'Only active system administrators can invite employees' }, 403)

  const body = await request.json() as { email?: string; full_name?: string; role?: string; factory_ids?: string[]; department_ids?: string[] }
  if (!body.email?.trim() || !body.full_name?.trim() || !body.role || !allowedRoles.has(body.role)) return json({ error: 'Email, full name, and a valid role are required' }, 400)
  const inviteResponse = await fetch(`${supabaseUrl}/auth/v1/invite`, { method: 'POST', headers: adminHeaders, body: JSON.stringify({ email: body.email.trim(), data: { full_name: body.full_name.trim(), role: body.role } }) })
  const invitePayload = await inviteResponse.json()
  if (!inviteResponse.ok) return json({ error: invitePayload.msg ?? invitePayload.message ?? 'Unable to invite employee' }, inviteResponse.status)
  const userId = invitePayload.id as string
  const profileResponse = await fetch(`${supabaseUrl}/rest/v1/profiles`, { method: 'POST', headers: { ...adminHeaders, Prefer: 'return=minimal' }, body: JSON.stringify({ id: userId, full_name: body.full_name.trim(), email: body.email.trim(), role: body.role, is_active: true }) })
  if (!profileResponse.ok) return json({ error: 'Auth user was invited but profile creation failed' }, 500)
  if (body.factory_ids?.length) { const accessResponse = await fetch(`${supabaseUrl}/rest/v1/employee_factory_access`, { method: 'POST', headers: { ...adminHeaders, Prefer: 'return=minimal' }, body: JSON.stringify(body.factory_ids.map((factoryId) => ({ employee_id: userId, factory_id: factoryId }))) }); if (!accessResponse.ok) return json({ error: 'Profile was created but factory access assignment failed' }, 500) }
  if (body.department_ids?.length) { const accessResponse = await fetch(`${supabaseUrl}/rest/v1/employee_department_access`, { method: 'POST', headers: { ...adminHeaders, Prefer: 'return=minimal' }, body: JSON.stringify(body.department_ids.map((departmentId) => ({ employee_id: userId, department_id: departmentId }))) }); if (!accessResponse.ok) return json({ error: 'Profile was created but department access assignment failed' }, 500) }
  return json({ id: userId, message: 'Employee invitation sent' }, 201)
})
