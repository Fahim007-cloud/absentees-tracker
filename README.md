# Student Absentees Tracker v2

A mobile-friendly attendance tracker built with React and Supabase. It supports role-based dashboards for administrators, teachers, and representatives, attendance marking, roster management, and PDF/Excel/CSV reports.

## Security setup

1. Create a Supabase project.
2. In **Authentication → Sign In / Providers**, disable public signups. Accounts must be created by an administrator.
3. Run `supabase-setup-v2.sql` in the Supabase SQL Editor. The script enables RLS and grants data access only to users with an `atrk_profiles` role.
4. Create the first administrator manually in **Authentication → Users**, then add its profile using the SQL example in `SETUP.md`.
5. Deploy the Edge Function:

   ```bash
   supabase login
   supabase link --project-ref nwqhigskbldybobcdrgv
   supabase secrets set APP_ORIGINS="https://absentcse.netlify.app"
   supabase functions deploy create-user
   ```

   Set `APP_ORIGINS` to a comma-separated allowlist when the app is hosted on additional domains.
6. Put only the project URL and publishable/anon key in `index.html`. Never put the service-role key in the browser or repository.

## Deploying

This is a static site. Deploy the entire folder, including `index.html`, `manifest.json`, `sw.js`, the icon files, and `netlify.toml`.

`netlify.toml` adds baseline security headers for Netlify deployments. Other static hosts must configure equivalent headers.

## Technology

- React 18 and Babel Standalone
- Supabase Auth, Postgres, and REST API
- html2canvas, jsPDF, and ExcelJS
- Vanilla service worker for application-shell caching

## Security properties

- Row Level Security is enabled on all v2 tables.
- Read policies require an authenticated profile with an allowed role; a logged-in account without a role receives no v2 data.
- The service-role key is used only inside the admin-protected Edge Function.
- Edge Function requests validate method, content type, body size, UUIDs, email addresses, roles, and password length, and restrict browser origins.
- CDN scripts are version-pinned and protected with Subresource Integrity.
- CSV exports neutralize spreadsheet formula prefixes.
- Large Supabase result sets are fetched in stable-order pages.
- The legacy `supabase-setup.sql` script creates tables with RLS enabled and no anonymous policies; `supabase-setup-v2.sql` also removes legacy anonymous policies when those tables already exist.

## Important

The v2 app requires a live Supabase connection. The service worker caches the application shell only; it does not cache student data or queue offline mutations.
