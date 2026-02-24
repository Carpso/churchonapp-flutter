---
description: Deploying Kingdom Infrastructure (VPS & Real-time)
---

# Kingdom Infrastructure Deployment

This guide ensures your private VPS infrastructure (Supabase/PostgreSQL) is optimized for real-time ride matching and spiritual notifications.

## 1. Database Performance Optimization
To ensure the Ride-On module stays fast during peak Sunday expansion, run the optimization script found in:
`supabase/migrations/20240224_optimize_matching.sql`

You can run this via the Supabase SQL Editor or CLI:
```bash
supabase db execute -f supabase/migrations/20240224_optimize_matching.sql
```

## 2. Notification Table Setup
Ensure your schema supports internal real-time alerts. Run this in the SQL Editor:
```sql
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- Enable Realtime for notifications
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
```

## 3. Real-time Ride Matching
Enable Realtime for ride tables to allow riders and drivers to see each other instantly:
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE ride_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE ride_registrations;
ALTER PUBLICATION supabase_realtime ADD TABLE delivery_requests;
```

## 4. Delivery & Finance Setup
Ensure your schema supports cargo missions and internal economy. Run this in the SQL Editor:
```sql
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
  status TEXT DEFAULT 'pending', -- 'pending', 'processed', 'failed'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

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

CREATE TABLE IF NOT EXISTS sms_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone_number TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT,
  status TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS tithe_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  amount DOUBLE PRECISION NOT NULL,
  transaction_id TEXT,
  period TEXT, -- 'Jan 2026', etc.
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

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

CREATE TABLE IF NOT EXISTS events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  description TEXT,
  location TEXT,
  event_date TIMESTAMP WITH TIME ZONE NOT NULL,
  church_id UUID REFERENCES churches(id), -- Null if inter-church
  price DOUBLE PRECISION DEFAULT 0.0,
  capacity INTEGER,
  category TEXT, -- 'Conference', 'Worship', 'Seminar'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS tickets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id UUID REFERENCES events(id),
  user_id UUID REFERENCES auth.users(id),
  status TEXT DEFAULT 'valid', -- 'valid', 'used', 'cancelled'
  purchased_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS groups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  description TEXT,
  avatar_url TEXT,
  church_id UUID REFERENCES churches(id), -- Null for inter-church groups
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

CREATE TABLE IF NOT EXISTS group_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id UUID REFERENCES groups(id),
  user_id UUID REFERENCES auth.users(id),
  role TEXT DEFAULT 'member', -- 'admin', 'member'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
  UNIQUE(group_id, user_id)
);

-- Update messages to support group_id
ALTER TABLE messages ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES groups(id);
```

## 5. Expansion & Work Mode Permissions
Ensure the `profiles` table has geo-sync and work-mode enablement:
```sql
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_work_mode BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS coins INTEGER DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone_number TEXT;
```
