# Student Absentees Tracker v2 — Setup Guide

This version uses Supabase Auth with three roles: Admin, Teacher, and Representative. It uses the `atrk_*` tables and does not read the legacy `students` or `absentees` tables.

## 1. Secure the Supabase project

1. Create or open the Supabase project.
2. In **Authentication → Sign In / Providers**, disable public signups.
3. Run `supabase-setup-v2.sql` in the SQL Editor after reviewing it. It enables RLS, replaces the v2 policies with role-gated policies, and installs an attendance identity trigger.
4. Do not use `supabase-setup.sql` for v2. That legacy script drops the old tables and recreates them without anonymous access. The v2 script also removes legacy anonymous policies without dropping existing legacy tables.

## 2. Create the first Admin account

1. In **Authentication → Users**, add an email and password with **Auto Confirm User** enabled.
2. Copy the new user's UUID.
3. Add its profile in the SQL Editor:

   ```sql
   insert into public.atrk_profiles (id, email, role)
   values ('PASTE-THE-UUID-HERE', 'admin@example.com', 'admin');
   ```

4. Sign in as that administrator and use the Admin Dashboard to create Teacher and Representative accounts.

New and reset passwords must contain 12–128 characters.

## 3. Deploy the Edge Function

From the project directory:

```bash
supabase login
supabase link --project-ref nwqhigskbldybobcdrgv
supabase secrets set APP_ORIGINS="https://absentcse.netlify.app"
supabase functions deploy create-user
```

`APP_ORIGINS` is a comma-separated allowlist of browser origins. Keep it limited to origins that host the app. The function accepts only admin sessions and never exposes the service-role key to the browser.

## 4. Deploy the app

Deploy the complete folder to Netlify or another static host. Keep `netlify.toml` when using Netlify so the security headers are applied. The browser file contains only the Supabase publishable/anon key.

## Attendance rules

Each date represents Morning and Afternoon sessions. A null status means Present; `absent`, `od`, and `unmarked` are explicit exceptions. Declared holidays are excluded from reports and bulk marking.

Report queries and roster loads use stable-order pagination so Supabase row limits do not silently truncate results. CSV exports prefix cells that could be interpreted as spreadsheet formulas.

## Verify the deployed policies

Run this read-only query in the Supabase SQL Editor:

```sql
select
  tablename,
  policyname,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'atrk_profiles',
    'atrk_students',
    'atrk_attendance',
    'atrk_holidays'
  )
order by tablename, policyname;
```

Confirm that v2 read policies require `atrk_current_role()` and that no `anon` policies or grants provide access to `atrk_*` or legacy tables.

## Offline behavior

The v2 app requires a live Supabase connection. The service worker caches the application shell only; it does not cache student data or synchronize offline mutations.
