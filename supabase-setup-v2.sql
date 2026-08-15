-- ============================================================
-- Student Absentees Tracker v2 — role-based auth schema
-- These are NEW tables (atrk_* prefix) — they do not touch or
-- collide with the old "students"/"absentees" tables from the
-- previous version of the app, which are left untouched.
--
-- Run this whole script once in Project → SQL Editor → New query.
-- ============================================================

create extension if not exists "uuid-ossp";

-- ---------- profiles (role linked to a Supabase Auth user) ----------
create table if not exists atrk_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role  text not null check (role in ('admin','teacher','representative')),
  created_at timestamptz not null default now()
);

-- ---------- student roster ----------
create table if not exists atrk_students (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  roll_no text not null unique,
  created_at timestamptz not null default now()
);

-- ---------- attendance records ----------
-- Only exceptions are stored (absent / od). No row for a student on a
-- given date means they were present that day.
create table if not exists atrk_attendance (
  id uuid primary key default uuid_generate_v4(),
  student_id uuid not null references atrk_students(id) on delete cascade,
  name text not null,
  roll_no text not null,
  date text not null,          -- 'YYYY-MM-DD'
  day  text not null,          -- 'Monday' etc.
  status text not null check (status in ('absent','od')),
  created_at timestamptz not null default now(),
  unique (student_id, date)    -- one status per student per day
);

-- ---------- helper functions used inside RLS policies ----------
create or replace function atrk_current_role()
returns text
language sql
security definer
set search_path = public
as $$
  select role from atrk_profiles where id = auth.uid();
$$;

create or replace function atrk_is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select atrk_current_role() = 'admin';
$$;

-- ---------- Row Level Security ----------
alter table atrk_profiles   enable row level security;
alter table atrk_students   enable row level security;
alter table atrk_attendance enable row level security;

-- profiles: everyone can read their own row; admins can read/write all rows
create policy "read own profile" on atrk_profiles for select
  to authenticated using (id = auth.uid() or atrk_is_admin());
create policy "admin manages profiles" on atrk_profiles for all
  to authenticated using (atrk_is_admin()) with check (atrk_is_admin());

-- students: any signed-in role can view; teacher/rep/admin can add;
-- only teacher/admin can delete (matches the brief — reps can add
-- students but only teachers/admins remove them)
create policy "signed-in users read students" on atrk_students for select
  to authenticated using (true);
create policy "teacher rep admin add students" on atrk_students for insert
  to authenticated with check (atrk_current_role() in ('teacher','representative','admin'));
create policy "teacher admin delete students" on atrk_students for delete
  to authenticated using (atrk_current_role() in ('teacher','admin'));

-- attendance: any signed-in role can view (teachers need it for reports);
-- only representative/admin can mark/unmark (that's their daily job)
create policy "signed-in users read attendance" on atrk_attendance for select
  to authenticated using (true);
create policy "rep admin insert attendance" on atrk_attendance for insert
  to authenticated with check (atrk_current_role() in ('representative','admin'));
create policy "rep admin delete attendance" on atrk_attendance for delete
  to authenticated using (atrk_current_role() in ('representative','admin'));

-- ============================================================
-- BOOTSTRAP: creating your first Admin account
-- ============================================================
-- The app can only create new users through an Admin-only Edge
-- Function — so the very first Admin has to be created by hand,
-- once, here in the dashboard:
--
-- 1. Go to Authentication → Users → "Add user" in your Supabase
--    dashboard. Enter an email + password, and check
--    "Auto Confirm User". Click Create.
-- 2. Copy the new user's UUID (shown in the users list).
-- 3. Run this, with your own values substituted in:
--
--    insert into atrk_profiles (id, email, role)
--    values ('PASTE-THE-UUID-HERE', 'your-admin-email@example.com', 'admin');
--
-- After that, you can log into the app with that email/password and
-- use the Admin Dashboard to create Teacher and Representative
-- accounts through the app itself.
