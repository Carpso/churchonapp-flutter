-- Seed free public radio stations
INSERT INTO public.radio_stations (id, name, stream_url, location, is_private)
VALUES 
  (gen_random_uuid(), 'Radio Christian Voice', 'https://stream.rcvstream.com:8000/stream', 'National', false),
  (gen_random_uuid(), 'ZNBC Radio 1', 'http://41.223.119.186:8000/znbc1', 'Zambia', false),
  (gen_random_uuid(), 'ZNBC Radio 2', 'http://41.223.119.186:8000/znbc2', 'Zambia', false),
  (gen_random_uuid(), 'ZNBC Radio 4', 'http://41.223.119.186:8000/znbc4', 'Zambia', false),
  (gen_random_uuid(), 'Phoenix FM', 'http://173.244.209.117:8000/phoenixfm', 'Lusaka', false),
  (gen_random_uuid(), 'Hot FM', 'http://173.244.209.117:8000/hotfm', 'Lusaka', false),
  (gen_random_uuid(), 'QFM', 'http://192.111.140.6:8102/stream', 'Lusaka', false),
  (gen_random_uuid(), 'One Love Radio', 'https://stream.oneloveradio.org:8000/stream', 'Lusaka', false),
  (gen_random_uuid(), 'K-LOVE Radio', 'https://emg.streamguys1.com/klove', 'Global', false),
  (gen_random_uuid(), 'Air1 Radio', 'https://emg.streamguys1.com/air1', 'Global', false),
  (gen_random_uuid(), 'Spirit FM', 'https://stream.radiojar.com/atdu3k9s1ceuv', 'Global', false),
  (gen_random_uuid(), 'TNL Radio', 'http://live.tnlradio.org:8000/stream', 'Lusaka', false),
  (gen_random_uuid(), 'Gospel Radio', 'https://icecast.swncdn.com/gospel', 'Global', false),
  (gen_random_uuid(), 'Radio Maria Zambia', 'http://net.radiomaria.org.ar:8000/Zamba', 'National', false),
  (gen_random_uuid(), 'Praise Radio', 'https://praiseradio.streamguys1.com/live', 'Global', false)
ON CONFLICT (name) DO NOTHING;
