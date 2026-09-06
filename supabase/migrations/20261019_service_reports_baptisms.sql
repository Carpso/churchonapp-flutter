-- service_reports.baptisms was collected in UI (_baptisms) but never persisted.
-- Also ensure offering/tithe split can be preserved if needed.

alter table public.service_reports
  add column if not exists baptisms integer not null default 0;

-- Optional: add tithes column to preserve split (offering currently stores offering+tithe)
alter table public.service_reports
  add column if not exists tithes numeric not null default 0;

comment on column public.service_reports.baptisms is 'Number of baptisms for this service';
comment on column public.service_reports.tithes is 'Tithe portion of offering (offering column stores total)';
