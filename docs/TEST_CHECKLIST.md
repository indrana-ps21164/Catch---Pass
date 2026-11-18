# Catch & Pass test checklist

## Verified locally

- `npm run build` — passed.
- `npm run lint` — runs successfully; current output contains React cascading-render warnings only.
- Vite development server — starts successfully from the project path containing `&`.
- Frontend contains no seeded order, employee, task, notification, shipment, or dashboard records.

## Requires a configured Supabase project

- [ ] Run migrations `202611180001` through `202611180026` in order.
- [ ] Create an invited Auth user and matching profile.
- [ ] Confirm an employee can sign in and sign out.
- [ ] Confirm password reset email and `/reset-password` flow.
- [ ] Confirm RLS prevents access to an unauthorized factory.
- [ ] Confirm administrator employee invitation and factory access assignment.
- [ ] Search/filter employees by name, role, factory, and department; invite an employee with exact department access.
- [ ] Open Settings and Permissions and verify environment status and role guidance are displayed.
- [ ] Verify the dashboard counters for awaiting acceptance, overdue tasks, ready-for-dispatch orders, and shipment records against authorized database rows.
- [ ] Create a factory and department.
- [ ] Create a draft order with a product line.
- [ ] Create a draft order with multiple product lines and customer/internal remarks.
- [ ] Search orders and filter by status and priority.
- [ ] Edit and submit a draft order.
- [ ] Open an order and verify its remarks and audit history reflect real changes.
- [ ] Cancel an order with a required reason.
- [ ] Upload and download a private order attachment.
- [ ] Create a workflow template with ordered steps.
- [ ] Create sequential, parallel, and conditional workflow templates; verify conditional definitions are required.
- [ ] Create a task and verify assignment visibility.
- [ ] Accept, reject, and request clarification on a task; verify non-accept responses require a reason.
- [ ] Start an accepted task, save progress, submit completion remarks, and approve it as an authorized manager.
- [ ] Upload task evidence and verify the file is stored in the private attachment bucket with task metadata.
- [ ] Run Complete & Pass with one individual recipient.
- [ ] Verify Complete & Pass shows a review summary and requires explicit confirmation before submission.
- [ ] Run Complete & Pass with multiple recipients.
- [ ] Run Complete & Pass collaboratively with a required lead.
- [ ] Repeat the same idempotency key and verify no duplicate handover.
- [ ] Verify handover notifications and history.
- [ ] Keep Notifications open and verify a new authorized notification appears without a page refresh.
- [ ] Record a partial shipment and verify remaining quantity protection.
- [ ] Record final shipment and verify order completion.
- [ ] Export an authorized order CSV report.
- [ ] Select order, delayed-order, task, handover, and shipment reports and export each authorized dataset as CSV.
- [ ] Open Order Tracking and verify live tasks, handovers, and shipments for an authorized order.
- [ ] Configure and invoke the email Edge Function with Resend test credentials.

Production readiness must not be claimed until the unchecked Supabase tests have been executed with multiple roles.
