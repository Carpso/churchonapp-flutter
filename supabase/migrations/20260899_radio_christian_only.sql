-- 20260899: Radio — Christian-only stations
-- Removes secular / test / invalid stations; seeds reliable global Christian streams.

-- 1. Delete non-Christian & invalid stations (matched by name)
DELETE FROM public.radio_stations
WHERE lower(name) IN (
  'hot fm',
  'one love radio',
  'phoenix fm',
  'qfm',
  'znbc radio 1',
  'znbc radio 2',
  'znbc radio 4',
  'private test station',
  'church on app radio'
);

-- 2. Refresh stream URLs on the remaining stations to the most stable public endpoints
UPDATE public.radio_stations
SET stream_url = 'https://emf.streamguys1.com/klove_mp3'
WHERE lower(name) = 'k-love radio';

UPDATE public.radio_stations
SET stream_url = 'https://emg.streamguys1.com/air1'
WHERE lower(name) = 'air1 radio';

UPDATE public.radio_stations
SET stream_url = 'https://emg.streamguys1.com/air1-worship'
WHERE lower(name) = 'air1 worship';

-- 3. Seed additional well-known Christian stations (worldwide)
INSERT INTO public.radio_stations (name, stream_url, location, is_private)
SELECT v.name, v.stream_url, v.location, false
FROM (VALUES
  ('TBN Radio',            'https://stream.tbn.org/tbnradio',                     'USA',          'TBN Radio'::text),
  ('Crossroads Radio',     'https://stream.crossroads.ca/live',                    'Canada',       'Crossroads Radio'),
  ('Family Radio',         'https://stream.familyradio.org/fr-mp3',                'USA',          'Family Radio'),
  ('Hope FM Kenya',        'https://icecast.hopefm.co.ke/hopefm',                  'Kenya',        'Hope FM Kenya'),
  ('Radio Puissance Espoir','https://radio.espoirfm.org/live',                     'DR Congo',     'Radio Puissance Espoir'),
  ('Inspiration FM Lagos', 'https://inspirationfm.radioca.st/stream',              'Nigeria',      'Inspiration FM Lagos'),
  ('Family Radio 316',     'https://stream.familyradio316.com/family316',          'Nigeria',      'Family Radio 316'),
  ('Spirit FM Zambia',     'https://stream.radiojar.com/atdu3k9s1ceuv',            'Global',       'Spirit FM Zambia'),
  ('Premier Christian',    'https://premier.live.wostreaming.net/web-mp3',         'UK',           'Premier Christian')
) AS v(name, stream_url, location, name_check)
WHERE NOT EXISTS (
  SELECT 1 FROM public.radio_stations s WHERE lower(s.name) = lower(v.name_check)
);