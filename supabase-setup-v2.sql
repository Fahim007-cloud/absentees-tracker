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
-- Session-level statuses, AM and PM. A status of null means Present:
-- the app treats every student as Present by default, so a brand-new
-- date with no records shows everyone as Present. Only exceptions
-- (absent / od / unmarked) are written down. 'unmarked' is an explicit
-- Not Marked status — a day deliberately removed from the Present
-- default (e.g. via bulk "Not Marked"), distinct from null.
create table if not exists atrk_attendance (
  id uuid primary key default uuid_generate_v4(),
  student_id uuid not null references atrk_students(id) on delete cascade,
  name text not null,
  roll_no text not null,
  date text not null,          -- 'YYYY-MM-DD'
  day  text not null,          -- 'Monday' etc.
  morning_status   text check (morning_status in ('absent','od','unmarked')),
  afternoon_status text check (afternoon_status in ('absent','od','unmarked')),
  afternoon_manual boolean not null default false,  -- PM was hand-edited, stop mirroring AM into it
  created_at timestamptz not null default now(),
  unique (student_id, date)    -- one record per student per day (AM + PM)
);

-- ---------- declared holidays ----------
-- Holidays are skipped by bulk marking and excluded from reports and
-- the attendance percentage.
create table if not exists atrk_holidays (
  id uuid primary key default uuid_generate_v4(),
  date text not null unique,   -- 'YYYY-MM-DD'
  reason text not null,
  created_at timestamptz not null default now()
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
alter table atrk_holidays   enable row level security;

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
-- representative/admin mark and correct — the app saves corrections with
-- upsert (INSERT ... ON CONFLICT DO UPDATE), so an update policy is
-- required alongside insert/delete. Teachers read-only here.
create policy "signed-in users read attendance" on atrk_attendance for select
  to authenticated using (true);
create policy "rep admin insert attendance" on atrk_attendance for insert
  to authenticated with check (atrk_current_role() in ('representative','admin'));
create policy "rep admin update attendance" on atrk_attendance for update
  to authenticated using (atrk_current_role() in ('representative','admin'))
  with check (atrk_current_role() in ('representative','admin'));
create policy "rep admin delete attendance" on atrk_attendance for delete
  to authenticated using (atrk_current_role() in ('representative','admin'));

-- holidays: everyone signed in can read (reports filter by them);
-- only admin declares/removes
create policy "signed-in users read holidays" on atrk_holidays for select
  to authenticated using (true);
create policy "admin manages holidays" on atrk_holidays for all
  to authenticated using (atrk_is_admin()) with check (atrk_is_admin());

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
--
-- If you previously ran an older version of this script that created
-- atrk_attendance with a single NOT NULL "status" column, migrate it
-- (adjust the mapping of your old statuses as needed):
--
--    alter table atrk_attendance
--      drop constraint if exists atrk_attendance_status_check,
--      add column if not exists morning_status text,
--      add column if not exists afternoon_status text,
--      add column if not exists afternoon_manual boolean not null default false;
--    update atrk_attendance set
--      morning_status = status, afternoon_status = status, afternoon_manual = true;
--    alter table atrk_attendance drop column status;
--    create unique index if not exists atrk_attendance_student_date_uidx
--      on atrk_attendance (student_id, date);
--
-- (If your live table already has the morning/afternoon columns, there
-- is nothing to do — "create table if not exists" will not touch it.)
