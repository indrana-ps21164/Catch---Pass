const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const resendApiKey = Deno.env.get('RESEND_API_KEY') ?? ''
const fromEmail = Deno.env.get('RESEND_FROM_EMAIL') ?? ''
const appBaseUrl = Deno.env.get('APP_BASE_URL') ?? ''

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })
const escapeHtml = (value: string) => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;')
const headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}`, 'Content-Type': 'application/json' }

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405)
  const authorization = request.headers.get('authorization') ?? ''
  if (!serviceRoleKey || authorization !== `Bearer ${serviceRoleKey}`) return json({ error: 'Unauthorized' }, 401)
  if (!supabaseUrl || !resendApiKey || !fromEmail) return json({ error: 'Email service secrets are not configured' }, 500)

  const { data: queue, error: queueError } = await fetch(`${supabaseUrl}/rest/v1/email_outbox?status=eq.pending&next_attempt_at=lte.${encodeURIComponent(new Date().toISOString())}&order=created_at.asc&limit=25`, { headers }).then(async (response) => ({ data: await response.json(), error: response.ok ? null : await response.text() }))
  if (queueError) return json({ error: queueError }, 502)
  const results: Array<{ id: string; status: string }> = []

  for (const item of queue as Array<{ id: string; notification_id: string; recipient_email: string; subject: string; attempts: number }>) {
    const processing = await fetch(`${supabaseUrl}/rest/v1/email_outbox?id=eq.${item.id}`, { method: 'PATCH', headers: { ...headers, Prefer: 'return=minimal' }, body: JSON.stringify({ status: 'processing', attempts: item.attempts + 1 }) })
    if (!processing.ok) continue
    const notificationResponse = await fetch(`${supabaseUrl}/rest/v1/notifications?id=eq.${item.notification_id}&select=title,body,task_id,order_id`, { headers })
    const notification = (await notificationResponse.json())[0] as { title?: string; body?: string; task_id?: string; order_id?: string } | undefined
    const actionUrl = appBaseUrl || '#'
    const emailResponse = await fetch('https://api.resend.com/emails', { method: 'POST', headers: { Authorization: `Bearer ${resendApiKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ from: fromEmail, to: [item.recipient_email], subject: item.subject, html: `<p>${escapeHtml(notification?.body ?? '')}</p><p><a href="${escapeHtml(actionUrl)}">Open Catch & Pass</a></p>` }) })
    if (emailResponse.ok) { await fetch(`${supabaseUrl}/rest/v1/email_outbox?id=eq.${item.id}`, { method: 'PATCH', headers: { ...headers, Prefer: 'return=minimal' }, body: JSON.stringify({ status: 'sent', sent_at: new Date().toISOString(), last_error: null }) }); results.push({ id: item.id, status: 'sent' }) } else { const errorText = await emailResponse.text(); const attempts = item.attempts + 1; const terminal = attempts >= 5; await fetch(`${supabaseUrl}/rest/v1/email_outbox?id=eq.${item.id}`, { method: 'PATCH', headers: { ...headers, Prefer: 'return=minimal' }, body: JSON.stringify({ status: terminal ? 'failed' : 'pending', last_error: errorText, next_attempt_at: new Date(Date.now() + Math.min(attempts * 15, 120) * 60_000).toISOString() }) }); results.push({ id: item.id, status: terminal ? 'failed' : 'pending' }) }
  }
  return json({ processed: results.length, results })
})
