# CATCH & PASS

Professional order workflow management for Wardena Group.

## Phase 1 status

The current phase provides the responsive application shell and design system:

- Dark navy workspace sidebar with responsive mobile navigation
- Dashboard overview with KPI cards, recent orders, task summary, activity timeline, and factory chart
- Search and status filtering on the recent orders table
- Interactive notification popover and navigation state
- Lucide React icons and a production-style typography/color system

The Phase 1 UI does not include presentation fixtures or seeded business records. All visible business data is loaded from Supabase; empty states are shown until authorized records exist.

## Run locally

```bash
npm install
npm run dev
```

Check the production bundle with:

```bash
npm run build
```

## Supabase connection plan

Phase 1 is intentionally not connected to a database yet. Before enabling database features, create a Supabase project and add a local `.env.local` file:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
```

Only the public Supabase URL and anon key belong in the browser. Service-role keys, database passwords, and Resend API keys must remain in Supabase Edge Functions or other server-side secrets. Phase 2 will add migrations, Auth, and Row Level Security policies.

## Planned structure

```text
src/
  App.tsx          # Phase 1 application shell
  App.css          # responsive workspace UI styles
  index.css        # global typography and reset
  components/      # reusable UI components (next phase)
  features/        # orders, factories, tasks, and workflow modules
  lib/             # Supabase client and shared utilities
supabase/
  migrations/      # database migrations
  functions/       # secure Edge Functions
```

## Phase sequence

1. Project shell, design system, authentication, database connection, and employee management
2. Factory, department, and order management
3. Workflow templates and task dependencies
4. Individual and collaborative task assignment
5. Manual handover wizard and acceptance/rejection
6. Notifications and email integration
7. Dashboard, reports, and exports
8. Security testing, backup preparation, and deployment

## Phase 1 Supabase setup

1. Create a Supabase project.
2. Copy `.env.example` to `.env.local` and replace both values with the project URL and public anon key from Supabase Project Settings > API.
3. In Supabase Authentication > Providers, keep Email enabled and turn off public sign-ups. Employees should be invited by an administrator.
4. Open Supabase SQL Editor and run `supabase/migrations/202611180001_phase1_foundation.sql`.
5. Create the first administrator in Supabase Authentication, then insert their matching profile with the `system_administrator` role using a protected admin workflow or SQL Editor.
6. Restart the Vite server after changing `.env.local` and open the local URL.

The browser only uses the public anon key. Never put a service-role key in `.env.local` or frontend code. The migration enables RLS on every Phase 1 table; policies will be extended as later modules are added.

## Phase 1 test checklist

- Without `.env.local`, the login page explains that Supabase is not configured.
- With valid Supabase settings, an invited employee can sign in.
- Invalid credentials show an error and do not open the dashboard.
- The profile menu signs out.
- The migration creates no business records and enables RLS. Administrators create factories through the application.
- Build verification: `npm run build`.

## Phase 2 progress

The first real database-backed modules are implemented:

- Factory list loaded from Supabase
- Administrator factory creation form protected by RLS
- Order list loaded from Supabase
- Draft order creation with customer, reference, factory, delivery date, and priority
- Empty states when the database contains no records

Run this migration in Supabase SQL Editor:

```text
supabase/migrations/202611180002_phase2_orders.sql
```

It creates `orders` and `order_items`, constraints, indexes, and RLS policies. The next migration adds an atomic order-plus-product-line transaction:

```text
supabase/migrations/202611180003_phase2_order_transaction.sql
```

The Factory screen now reads factories and departments from Supabase and allows administrators to create both. The Orders screen creates a draft order with its first product line through the transactional database function. Editing, submission, attachments, and order tracking remain in the next Phase 2 increment.

The order list now opens a detail view showing product lines and allows the creator or an authorized manager to submit a draft. Run `supabase/migrations/202611180004_order_submission.sql` after the previous migrations to enable the validated submission action.

Draft orders can now be edited. Orders can be cancelled only with a required reason, and the cancellation reason is retained in the database. Run `supabase/migrations/202611180005_order_cancellation.sql` to enable this field and constraint.

Workflow foundation is now available through `supabase/migrations/202611180006_workflow_task_handover_foundation.sql`, with a policy repair in `202611180007_task_rls_policy_repair.sql`. The My Tasks screen reads authorized task assignments from Supabase and supports accept/reject responses; rejection requires a reason.

Complete & Pass is now implemented through `202611180008_complete_and_pass_transaction.sql`, with the broad notification insert policy removed by `202611180009_remove_broad_notification_insert.sql`. The screen requires a manually selected recipient, supports individual or collaborative mode, requires a collaborative lead, and uses an idempotency key to prevent duplicate handovers.

Notifications and Handover History screens now read real records from Supabase. Notifications can be marked individually or all at once; handover history is read-only and preserves the transaction record.

Workflow Management now includes an atomic template builder with factory selection and ordered department steps. Run `supabase/migrations/202611180010_workflow_template_transaction.sql` to enable template creation.

Private file attachments are supported for order records through `supabase/migrations/202611180011_secure_attachments.sql`. The migration creates a private Storage bucket, metadata table, and storage policies. Order details can upload and download authorized attachments.

Shipment recording and order summary CSV export are available after running `supabase/migrations/202611180012_shipments_reports.sql`. Shipment quantities are validated against ordered and already-shipped quantities, and completed orders are updated automatically when all quantities are shipped.

Email delivery uses the outbox migration `supabase/migrations/202611180013_notification_email_outbox.sql` and the Edge Function at `supabase/functions/send-notification-email/index.ts`. Configure these server-side secrets in Supabase, never in the frontend:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
RESEND_API_KEY
RESEND_FROM_EMAIL
APP_BASE_URL
```

Invoke the Edge Function from a protected scheduler or server process using the service-role bearer token. In-app notifications are saved even when email delivery is unavailable; failed deliveries retry up to five times before being marked failed.

The Overview dashboard now displays live counts from authorized Supabase records, and Team Directory lists only profiles allowed by the database policies. Both screens show empty/zero states without inserting sample employees or metrics.

Authentication now includes a real Supabase password-reset flow: request a reset link from the login page, configure the Supabase Auth redirect URL for `/reset-password`, then set the new password in the recovery screen.

Navigation visibility now follows the signed-in profile role. This is only a usability layer; all data access and writes remain enforced by Supabase RLS policies.

Employee invitations use the protected `supabase/functions/invite-employee/index.ts` Edge Function. It validates the caller as an active system administrator, invites the Auth user, creates the profile, and assigns authorized factories. The service-role key is used only in the Edge Function.

## Cloudflare Pages deployment

Build settings:

```text
Build command: npm run build
Build output directory: dist
```

Add only these browser-safe variables to the Cloudflare Pages project:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

Deploy Supabase Edge Functions separately and configure their server-side secrets in Supabase. Never add `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY`, or database passwords to Cloudflare browser environment variables.

Workspace modules use React Router browser URLs. The committed `public/_redirects` file sends direct Cloudflare Pages links back to the SPA entry point.

Team Tasks now creates and assigns tasks through the atomic function in `supabase/migrations/202611180015_task_creation_transaction.sql`. It validates the order factory, department, active employee, and manager role before creating the assignment, notification, and audit record.

Employee department authorization is stored by `supabase/migrations/202611180016_employee_department_access.sql`. The Team Directory now supports employee search and role/factory/department filters, and administrators choose exact department access during invitations.

Task accept/reject/clarification responses now use the atomic function in `supabase/migrations/202611180017_task_response_transaction.sql`, which updates the assignment, task status, history, notification, and audit record together. Rejection and clarification requests require an explanation.

Finish the migration sequence with `202611180018_authenticated_data_api_grants.sql`. It grants authenticated browser access to the tables while RLS continues to control which rows are visible.

Order update security is finalized by `202611180019_order_update_security.sql`: creators may edit drafts only, while cancellation requires the validated `cancel_order` function and a reason.

Order creation now supports multiple product lines plus customer and internal remarks through the atomic `create_draft_order_with_details` function in `202611180020_order_details_transaction.sql`.

Task work lifecycle updates are protected by `202611180021_task_lifecycle_transaction.sql`: assigned employees can start, update progress, block, and submit work with completion remarks; authorized managers can approve submitted tasks.

Settings and Permissions show runtime configuration status and the role capability matrix; actual authorization remains enforced by Supabase RLS and database functions.

In-app notifications update through a recipient-scoped Supabase Realtime subscription after applying `202611180022_notifications_realtime.sql`; the initial list still loads from the authorized Notifications query.

Reports now provide live selectable Order Summary, Delayed Orders, Task Completion, Handover History, and Shipment datasets, each with authorized CSV export.

The dashboard now includes live counters for awaiting acceptance, overdue tasks, ready-for-dispatch orders, and shipment records in addition to order, task, and handover totals.

Complete & Pass now has a review step that summarizes the source task, mode, recipients, instructions, outcome, due date, and priority before the atomic handover transaction is confirmed.

My Tasks supports task evidence uploads through the private `catch-pass-attachments` bucket and the existing task-scoped attachment RLS policies.

Private attachment downloads are repaired by `202611180023_attachment_storage_access_repair.sql`: authorized record participants can download files while unrelated users remain denied by Storage and table-level RLS.

Workflow templates now record sequential, parallel, or conditional structure metadata through `202611180024_workflow_structure_transaction.sql`. Conditional templates require a condition definition; no employee is selected automatically.

Order history is populated by the server-side audit trigger in `202611180025_order_audit_history.sql` for creation and meaningful order updates/status changes.

The requested Order Creation factory list is added as persistent master data by `202611180026_requested_factory_master_data.sql`: CM, VCO, Cream, Recart, Flour, Chip, Amino, Sugar, and Other. This migration adds only the requested factory configuration; it does not seed orders, employees, tasks, or dashboard data.

The Orders module also provides client-side search by order number, customer, or customer reference, plus status and priority filters over the authorized Supabase result set.

Order Tracking now loads authorized workflow tasks, handovers, and shipment records for the selected order instead of displaying only a static summary.
