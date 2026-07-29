-- Add duration column to klips for Klip v1 (2026-08-07)
alter table public.klips
  add column if not exists duration integer;
