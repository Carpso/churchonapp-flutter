-- ########################################################
-- KINGDOM INFRASTRUCTURE: CONSOLIDATED SOVEREIGN DEPLOYMENT
-- ########################################################

-- 1. NOTIFICATIONS & REALTIME
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- 2. LOGISTICS (RIDE-ON & CARGO)
CREATE TABLE IF NOT EXISTS ride_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rider_id UUID REFERENCES auth.users(id),
  driver_id UUID REFERENCES auth.users(id),
  pickup_lat DOUBLE PRECISION NOT NULL,
  pickup_lng DOUBLE PRECISION NOT NULL,
  dest_lat DOUBLE PRECISION NOT NULL,
  dest_lng DOUBLE PRECISION NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS delivery_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID REFERENCES auth.users(id),
  driver_id UUID REFERENCES auth.users(id),
  item_description TEXT NOT NULL,
  item_category TEXT NOT NULL,
  weight TEXT NOT NULL,
  pickup_lat DOUBLE PRECISION NOT NULL,
  pickup_lng DOUBLE PRECISION NOT NULL,
  dest_lat DOUBLE PRECISION NOT NULL,
  dest_lng DOUBLE PRECISION NOT NULL,
  offered_fare DOUBLE PRECISION NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER PUBLICATION supabase_realtime ADD TABLE ride_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE delivery_requests;

-- 3. FINANCE & STEWARDSHIP
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  amount DOUBLE PRECISION NOT NULL,
  type TEXT NOT NULL,
  reference_id TEXT,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS payout_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  amount DOUBLE PRECISION NOT NULL,
  mobile_number TEXT NOT NULL,
  network TEXT NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS tithe_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  amount DOUBLE PRECISION NOT NULL,
  transaction_id TEXT,
  period TEXT,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 4. CHURCHES & CONGREGATIONS
CREATE TABLE IF NOT EXISTS churches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  primary_color TEXT DEFAULT '#8B5CF6',
  logo_url TEXT,
  pastor_name TEXT,
  contact_phone TEXT,
  is_verified BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 5. SERMONS (PROPHETIC ARCHIVE)
CREATE TABLE IF NOT EXISTS sermons (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  preacher TEXT NOT NULL,
  description TEXT,
  thumbnail_url TEXT,
  video_url TEXT NOT NULL,
  is_live BOOLEAN DEFAULT false,
  church_id UUID REFERENCES churches(id),
  transcript TEXT,
  ai_summary TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- AI Search Index (Prophetic Retrieval)
-- Use a safer approach for generated columns
DO $$ 
BEGIN 
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='sermons' AND column_name='fts') THEN
    ALTER TABLE sermons ADD COLUMN fts tsvector GENERATED ALWAYS AS (
      to_tsvector('english', title || ' ' || preacher || ' ' || COALESCE(transcript, ''))
    ) STORED;
  END IF;
END $$;

DROP INDEX IF EXISTS sermons_fts_idx;
CREATE INDEX sermons_fts_idx ON sermons USING GIN (fts);

-- 6. EVENTS & TICKETING
CREATE TABLE IF NOT EXISTS events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  description TEXT,
  location TEXT,
  event_date TIMESTAMP WITH TIME ZONE NOT NULL,
  church_id UUID REFERENCES churches(id),
  price DOUBLE PRECISION DEFAULT 0.0,
  capacity INTEGER,
  category TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS tickets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id UUID REFERENCES events(id),
  user_id UUID REFERENCES auth.users(id),
  status TEXT DEFAULT 'valid',
  purchased_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 7. COMMUNITIES & INTER-CHURCH
CREATE TABLE IF NOT EXISTS channels (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  church_id UUID REFERENCES churches(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT DEFAULT 'public', -- 'public', 'private', 'group'
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  channel_id UUID REFERENCES channels(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  content TEXT,
  media_url TEXT,
  group_id UUID, -- Will link to groups table below
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS groups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  avatar_url TEXT,
  church_id UUID REFERENCES churches(id),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

ALTER TABLE messages ADD CONSTRAINT fk_messages_group FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS group_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id UUID REFERENCES groups(id),
  user_id UUID REFERENCES auth.users(id),
  role TEXT DEFAULT 'member',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  UNIQUE(group_id, user_id)
);

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE channels;

-- 8. INFRASTRUCTURE LOGS
CREATE TABLE IF NOT EXISTS sms_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone_number TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT,
  status TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 9. PROFILE ENHANCEMENTS & MULTI-CURRENCY
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_work_mode BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS coins INTEGER DEFAULT 0; -- Legacy CC
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS balance_cc DOUBLE PRECISION DEFAULT 0.0; -- High-fidelity CC
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS balance_zmw DOUBLE PRECISION DEFAULT 0.0; -- Zambian Kwacha
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS currency_preference TEXT DEFAULT 'ZMW';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone_number TEXT;

-- 10. PROPHETIC NAVIGATION (Route Optimization)
CREATE TABLE IF NOT EXISTS route_optimizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  mission_id UUID REFERENCES delivery_requests(id),
  optimized_path JSONB, -- Stores the AI recommended coordinates
  efficiency_rating DOUBLE PRECISION,
  prophetic_insight TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 11. APOSTOLIC RESOURCE ALLOCATION
CREATE TABLE IF NOT EXISTS resource_allocations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  hub_id UUID REFERENCES churches(id),
  resource_type TEXT NOT NULL, -- chair, bible, fuel, welfare, etc.
  predicted_need_quantity INTEGER,
  actual_allocation_quantity INTEGER DEFAULT 0,
  is_dispatched BOOLEAN DEFAULT false,
  prophetic_justification TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 12. LENCO GLOBAL PAYOUTS
CREATE TABLE IF NOT EXISTS lenco_payouts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  amount DOUBLE PRECISION NOT NULL,
  currency TEXT DEFAULT 'ZMW',
  recipient_phone TEXT NOT NULL,
  recipient_network TEXT NOT NULL, -- mtn, airtel, zamtel
  lenco_reference TEXT,
  status TEXT DEFAULT 'pending', -- pending, successful, failed
  error_log TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 13. SOVEREIGN SOCIAL ENGINE
CREATE TABLE IF NOT EXISTS social_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT,
  media_url TEXT,
  media_type TEXT, -- image, video, document
  likes_count INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  prophetic_weight DOUBLE PRECISION DEFAULT 0.0,
  category TEXT DEFAULT 'general',
  is_moderated BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS social_likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES social_posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  UNIQUE(post_id, user_id)
);

CREATE TABLE IF NOT EXISTS social_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID REFERENCES social_posts(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 14. PROPHETIC SURVEILLANCE DATA
CREATE TABLE IF NOT EXISTS growth_heatmap_data (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  weight DOUBLE PRECISION DEFAULT 1.0,
  region_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 15. MESSAGE ENHANCEMENTS (Stickers & Files)
ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT 'text'; -- text, image, file, sticker
ALTER TABLE messages ADD COLUMN IF NOT EXISTS sticker_id TEXT;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS file_name TEXT;
