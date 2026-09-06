-- Song Lyrics phantom: lib/features/home/data/lyric_service.dart queries from('lyrics')
-- but real table is worship_lyrics (20260723... + 20260840). Keep legacy compat via view.

create or replace view public.lyrics as
  select
    id,
    title,
    artist,
    lyrics,
    category,
    tenant_id,
    church_id,
    created_by,
    created_at
  from public.worship_lyrics;

grant select on public.lyrics to anon, authenticated;
