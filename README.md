# CATCH & PASS

Professional order workflow management for Wardena Group.

## Phase 1 status

The current phase provides the responsive application shell and design system:

- Dark navy workspace sidebar with responsive mobile navigation
- Dashboard overview with KPI cards, recent orders, task summary, activity timeline, and factory chart
- Search and status filtering on the recent orders table
- Interactive notification popover and navigation state
- Lucide React icons and a production-style typography/color system

The order rows shown in the Phase 1 UI are presentation fixtures only. No production data is connected yet; Phase 2 will introduce the Supabase-backed factory, department, and order modules.

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
