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
  email text not null check (char_length(email) between 3 and 320),
  role  text not null check (role in ('admin','teacher','representative')),
  created_at timestamptz not null default now()
);

-- ---------- student roster ----------
create table if not exists atrk_students (
  id uuid primary key default uuid_generate_v4(),
  name text not null check (char_length(name) between 1 and 200),
  roll_no text not null unique check (char_length(roll_no) between 1 and 100),
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
  date text not null check (date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  day  text not null check (day in ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
  morning_status   text check (morning_status in ('absent','od','unmarked')),
  afternoon_status text check (afternoon_status in ('absent','od','unmarked')),
  afternoon_manual boolean not null default false,  -- PM was hand-edited, stop mirroring AM into it
  created_at timestamptz not null default now(),
  unique (student_id, date)    -- one record per student per day (AM + PM)
);

create or replace function public.atrk_attendance_identity()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  parsed_date date;
  student_name text;
  student_roll text;
begin
  begin
    parsed_date := new.date::date;
  exception when others then
    raise exception 'Invalid attendance date';
  end;

  if to_char(parsed_date, 'YYYY-MM-DD') <> new.date then
    raise exception 'Invalid attendance date';
  end if;

  new.date := to_char(parsed_date, 'YYYY-MM-DD');
  new.day := case extract(isodow from parsed_date)
    when 1 then 'Monday'
    when 2 then 'Tuesday'
    when 3 then 'Wednesday'
    when 4 then 'Thursday'
    when 5 then 'Friday'
    when 6 then 'Saturday'
    when 7 then 'Sunday'
  end;

  select name, roll_no into student_name, student_roll
  from public.atrk_students
  where id = new.student_id;

  if student_name is null then
    raise exception 'Student does not exist';
  end if;

  new.name := student_name;
  new.roll_no := student_roll;
  return new;
end;
$$;

drop trigger if exists atrk_attendance_identity on public.atrk_attendance;
create trigger atrk_attendance_identity
before insert or update on public.atrk_attendance
for each row execute function public.atrk_attendance_identity();

-- ---------- declared holidays ----------
-- Holidays are skipped by bulk marking and excluded from reports and
-- the attendance percentage.
create table if not exists atrk_holidays (
  id uuid primary key default uuid_generate_v4(),
  date text not null unique check (date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'),
  reason text not null check (char_length(reason) between 1 and 500),
  created_at timestamptz not null default now()
);

create or replace function public.atrk_validate_holiday_date()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  parsed_date date;
begin
  begin
    parsed_date := new.date::date;
  exception when others then
    raise exception 'Invalid holiday date';
  end;

  if to_char(parsed_date, 'YYYY-MM-DD') <> new.date then
    raise exception 'Invalid holiday date';
  end if;

  new.date := to_char(parsed_date, 'YYYY-MM-DD');
  return new;
end;
$$;

drop trigger if exists atrk_validate_holiday_date on public.atrk_holidays;
create trigger atrk_validate_holiday_date
before insert or update on public.atrk_holidays
for each row execute function public.atrk_validate_holiday_date();

-- ---------- helper functions used inside RLS policies ----------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated, service_role;
grant usage on schema private to authenticated;

create or replace function private.atrk_current_role()
returns text
language sql
security definer
set search_path = pg_catalog, public
as $$
  select role from public.atrk_profiles where id = auth.uid();
$$;

create or replace function private.atrk_is_admin()
returns boolean
language sql
security definer
set search_path = pg_catalog, public
as $$
  select private.atrk_current_role() = 'admin';
$$;

revoke all on function private.atrk_current_role() from public, anon, authenticated, service_role;
revoke all on function private.atrk_is_admin() from public, anon, authenticated, service_role;
revoke all on function public.atrk_attendance_identity() from public, anon, authenticated, service_role;
revoke all on function public.atrk_validate_holiday_date() from public, anon, authenticated, service_role;
grant execute on function private.atrk_current_role() to authenticated;
grant execute on function private.atrk_is_admin() to authenticated;

-- ---------- Row Level Security ----------
alter table public.atrk_profiles   enable row level security;
alter table public.atrk_students   enable row level security;
alter table public.atrk_attendance enable row level security;
alter table public.atrk_holidays   enable row level security;

revoke all on public.atrk_profiles from anon;
revoke all on public.atrk_students from anon;
revoke all on public.atrk_attendance from anon;
revoke all on public.atrk_holidays from anon;

do $$
declare
  policy_record record;
begin
  for policy_record in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('atrk_profiles', 'atrk_students', 'atrk_attendance', 'atrk_holidays')
  loop
    execute format(
      'drop policy %I on %I.%I',
      policy_record.policyname,
      policy_record.schemaname,
      policy_record.tablename
    );
  end loop;
end;
$$;

create policy "read own profile" on public.atrk_profiles for select
  to authenticated using (id = auth.uid() or private.atrk_is_admin());
create policy "admin manages profiles" on public.atrk_profiles for all
  to authenticated using (private.atrk_is_admin()) with check (private.atrk_is_admin());

create policy "signed-in users read students" on public.atrk_students for select
  to authenticated using (private.atrk_current_role() in ('admin','teacher','representative'));
create policy "teacher rep admin add students" on public.atrk_students for insert
  to authenticated with check (private.atrk_current_role() in ('teacher','representative','admin'));
create policy "teacher admin delete students" on public.atrk_students for delete
  to authenticated using (private.atrk_current_role() in ('teacher','admin'));

create policy "signed-in users read attendance" on public.atrk_attendance for select
  to authenticated using (private.atrk_current_role() in ('admin','teacher','representative'));
create policy "rep admin insert attendance" on public.atrk_attendance for insert
  to authenticated with check (private.atrk_current_role() in ('representative','admin'));
create policy "rep admin update attendance" on public.atrk_attendance for update
  to authenticated using (private.atrk_current_role() in ('representative','admin'))
  with check (private.atrk_current_role() in ('representative','admin'));
create policy "rep admin delete attendance" on public.atrk_attendance for delete
  to authenticated using (private.atrk_current_role() in ('representative','admin'));

create policy "signed-in users read holidays" on public.atrk_holidays for select
  to authenticated using (private.atrk_current_role() in ('admin','teacher','representative'));
create policy "admin manages holidays" on public.atrk_holidays for all
  to authenticated using (private.atrk_is_admin()) with check (private.atrk_is_admin());

drop function if exists public.atrk_current_role();
drop function if exists public.atrk_is_admin();

do $$
declare
  legacy_table text;
  policy_record record;
begin
  foreach legacy_table in array array['students', 'absentees'] loop
    if to_regclass('public.' || legacy_table) is not null then
      execute format('alter table public.%I enable row level security', legacy_table);
      execute format('revoke all on public.%I from anon', legacy_table);
      for policy_record in
        select schemaname, tablename, policyname
        from pg_policies
        where schemaname = 'public'
          and tablename = legacy_table
      loop
        execute format(
          'drop policy %I on %I.%I',
          policy_record.policyname,
          policy_record.schemaname,
          policy_record.tablename
        );
      end loop;
    end if;
  end loop;
end;
$$;

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
