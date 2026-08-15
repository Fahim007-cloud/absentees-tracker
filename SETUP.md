# Student Absentees Tracker v2 — Setup Guide

This version adds email/password login with three roles (Admin, Teacher,
Representative), an "On Duty" attendance status, and date-range PDF
reports. It uses **new database tables** (`atrk_*` prefix) in the same
Supabase project as before — your old `students`/`absentees` tables
from the previous version are untouched.

## 1. Run the database setup

Supabase dashboard → **SQL Editor** → New query → paste the entire
contents of `supabase-setup-v2.sql` → Run.

This creates:
- `atrk_profiles` — links a login to a role (admin/teacher/representative)
- `atrk_students` — the roster
- `atrk_attendance` — daily absent/OD records
- Row Level Security policies for all three

## 2. Create your first Admin account

The app can only create new users through an **Admin-only** function —
so the very first Admin has to be created by hand, once:

1. Supabase dashboard → **Authentication → Users → Add user**
2. Enter an email + password, check **"Auto Confirm User"**, click Create
3. Copy that user's UUID from the users list
4. Back in the SQL Editor, run (with your own values):
   ```sql
   insert into atrk_profiles (id, email, role)
   values ('PASTE-THE-UUID-HERE', 'your-admin-email@example.com', 'admin');
   ```

You can now log into the app with that email/password as Admin, and
create Teacher/Representative accounts from the Admin Dashboard itself.

## 3. Deploy the Edge Function

This is what lets the Admin Dashboard create new users securely — the
function runs on Supabase's servers and is the only place the secret
`service_role` key is ever used. It's never in `index.html`.

Install the Supabase CLI if you don't have it, then from this project
folder:

```bash
supabase login
supabase link --project-ref nwqhigskbldybobcdrgv
supabase functions deploy create-user
```

That's it — `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` are all injected automatically by Supabase
inside the function. Nothing to configure by hand.

## 4. Deploy the app itself

Same as before — this is a static site, no build step. Deploy the
**whole folder** (`index.html`, `manifest.json`, `sw.js`, the icon
files) to Netlify, GitHub Pages, or wherever you're hosting it. The
`supabase/` folder and `.sql`/`.md` files aren't needed by the deployed
site — those are just for your own setup reference.

## How attendance percentage is calculated

There's no school calendar built in, so "total days" is defined as
**the number of distinct dates in the selected range that have at
least one attendance record** — i.e. days someone actually took
attendance. For each student:

- **Absent** = their absent records in that range
- **OD** = their On Duty records in that range
- **Present** = total session days − Absent − OD
- **Percentage** = (Present + OD) ÷ total session days

OD counts toward the percentage as if present, since the student was
on official duty rather than truant. If you'd rather OD not count
toward the percentage, that's a one-line change I can make.

## What's different from the previous version

This build does **not** include the offline-mode/sync-queue system
from the previous version — between the new auth layer, three
dashboards, and PDF reporting, adding full offline support on top
would be a substantial second project. Everything here requires a
live connection. Let me know if you want offline support layered in
next.
