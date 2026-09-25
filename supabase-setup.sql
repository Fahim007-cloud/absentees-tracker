-- ============================================================
-- Student Absentees Tracker — Supabase setup
-- ⚠️ This REPLACES the "students" and "absentees" tables from the
-- earlier Attendance Manager app with a new structure (roll_no
-- instead of roll, and absentees linked to students by id).
-- Any existing data in those two tables will be permanently deleted.
--
-- Run this whole script once in Project → SQL Editor → New query.
-- ============================================================

create extension if not exists "uuid-ossp";

drop table if exists absentees cascade;
drop table if exists students cascade;

-- ---------- students (permanent roster) ----------
create table students (
  id      uuid primary key default uuid_generate_v4(),
  name    text not null,
  roll_no text not null unique,
  created_at timestamptz not null default now()
);

-- ---------- absentees (daily log) ----------
create table absentees (
  id         uuid primary key default uuid_generate_v4(),
  student_id uuid not null references students(id) on delete cascade,
  name       text not null,
  roll_no    text not null,
  date       text not null,   -- e.g. '2026-07-24'
  day        text not null,   -- e.g. 'Friday'
  created_at timestamptz not null default now(),
  unique (student_id, date)   -- prevents duplicate absent entries same day
);

-- ---------- Row Level Security ----------
alter table public.students  enable row level security;
alter table public.absentees enable row level security;

revoke all on public.students from anon;
revoke all on public.absentees from anon;
