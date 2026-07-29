-- ═══════════════════════════════════════════════════════════════
-- CHURCH ON APP - PRODUCTION MISSING TABLES & HARDENING
-- Creates all tables referenced by code but missing from DB
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. COA PAYMENTS TABLE (for Lipila payment tracking) ────────
CREATE TABLE IF NOT EXISTS public.coa_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  payment_ref TEXT NOT NULL UNIQUE,
  amount NUMERIC(12,2) NOT NULL,
  currency TEXT DEFAULT 'ZMW',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'initiated', 'awaiting_pin', 'approved', 'completed', 'settled', 'failed', 'rejected', 'cancelled', 'refunded')),
  payment_method TEXT DEFAULT 'mobile_money',
  network TEXT,
  phone_number TEXT,
  description TEXT,
  category TEXT DEFAULT 'giving',
  recipient_name TEXT,
  recipient_account TEXT,
  metadata JSONB DEFAULT '{}',
  idempotency_key TEXT UNIQUE,
  settled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.coa_payments ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "coa_payments_select" ON public.coa_payments FOR SELECT USING (
    auth.uid() = user_id OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'pastor', 'bishop', 'treasurer'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "coa_payments_insert" ON public.coa_payments FOR INSERT WITH CHECK (
    auth.uid() = user_id OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "coa_payments_update" ON public.coa_payments FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_coa_payments_user ON public.coa_payments(user_id);
CREATE INDEX IF NOT EXISTS idx_coa_payments_ref ON public.coa_payments(payment_ref);
CREATE INDEX IF NOT EXISTS idx_coa_payments_status ON public.coa_payments(status);
CREATE INDEX IF NOT EXISTS idx_coa_payments_created ON public.coa_payments(created_at DESC);

-- ── 2. CHURCH COMPETITIONS TABLE (for Bible quiz) ──────────────
CREATE TABLE IF NOT EXISTS public.church_competitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id),
  title TEXT NOT NULL,
  description TEXT,
  pin_code TEXT NOT NULL UNIQUE,
  scheduled_for TIMESTAMPTZ NOT NULL,
  question_count INT DEFAULT 10,
  difficulty TEXT DEFAULT 'Mixed',
  entry_fee NUMERIC(10,2) DEFAULT 0,
  prize_pool NUMERIC(10,2) DEFAULT 0,
  max_participants INT DEFAULT 100,
  status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled')),
  winner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.church_competitions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "competitions_select" ON public.church_competitions FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "competitions_insert" ON public.church_competitions FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'pastor', 'bishop'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "competitions_update" ON public.church_competitions FOR UPDATE USING (
    created_by = auth.uid() OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_competitions_tenant ON public.church_competitions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_competitions_pin ON public.church_competitions(pin_code);
CREATE INDEX IF NOT EXISTS idx_competitions_status ON public.church_competitions(status);

-- ── 3. ROLE ASSIGNMENTS TABLE ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.role_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_name TEXT NOT NULL,
  tenant_id UUID REFERENCES public.tenants(id),
  assigned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  rejected_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "role_assignments_select" ON public.role_assignments FOR SELECT USING (
    auth.uid() = user_id OR 
    auth.uid() = assigned_by OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "role_assignments_insert" ON public.role_assignments FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'pastor', 'bishop'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "role_assignments_update" ON public.role_assignments FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_role_assignments_user ON public.role_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_role_assignments_tenant ON public.role_assignments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_role_assignments_status ON public.role_assignments(status);

-- ── 4. TENANT ROLES TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tenant_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id),
  role_name TEXT NOT NULL,
  display_name TEXT,
  description TEXT,
  permissions JSONB DEFAULT '[]',
  is_system_role BOOLEAN DEFAULT false,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(tenant_id, role_name)
);

ALTER TABLE public.tenant_roles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "tenant_roles_select" ON public.tenant_roles FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "tenant_roles_insert" ON public.tenant_roles FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "tenant_roles_update" ON public.tenant_roles FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ── 5. NOTIFICATIONS TABLE WITH PROPER RLS ─────────────────────
ALTER TABLE IF EXISTS public.notifications ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "notifications_select" ON public.notifications FOR SELECT USING (
    auth.uid() = user_id OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "notifications_insert" ON public.notifications FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "notifications_update" ON public.notifications FOR UPDATE USING (
    auth.uid() = user_id OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON public.notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON public.notifications(created_at DESC);

-- ── 6. SERVICE REPORTS TABLE (if not exists) ───────────────────
CREATE TABLE IF NOT EXISTS public.service_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id),
  church_id UUID REFERENCES public.churches(id),
  service_date DATE NOT NULL,
  service_type TEXT NOT NULL DEFAULT 'sunday',
  attendance INT DEFAULT 0,
  new_members INT DEFAULT 0,
  salvations INT DEFAULT 0,
  baptisms INT DEFAULT 0,
  offering_amount NUMERIC(12,2) DEFAULT 0,
  tithe_amount NUMERIC(12,2) DEFAULT 0,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.service_reports ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "service_reports_select" ON public.service_reports FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role IN ('superadmin', 'employee', 'pastor', 'bishop', 'treasurer') OR tenant_id = service_reports.tenant_id))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "service_reports_insert" ON public.service_reports FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'pastor', 'bishop'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_service_reports_tenant_date ON public.service_reports(tenant_id, service_date DESC);

-- ── 7. RIDE REQUESTS TABLE (for Carpso Ride) ───────────────────
CREATE TABLE IF NOT EXISTS public.ride_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  pickup_lat NUMERIC(10,7) NOT NULL,
  pickup_lng NUMERIC(10,7) NOT NULL,
  pickup_address TEXT,
  dropoff_lat NUMERIC(10,7) NOT NULL,
  dropoff_lng NUMERIC(10,7) NOT NULL,
  dropoff_address TEXT,
  distance_km NUMERIC(8,2),
  estimated_fare NUMERIC(10,2),
  actual_fare NUMERIC(10,2),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'searching', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled')),
  vehicle_type TEXT DEFAULT 'standard',
  payment_method TEXT DEFAULT 'mobile_money',
  rating INT CHECK (rating >= 1 AND rating <= 5),
  review TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "ride_requests_select" ON public.ride_requests FOR SELECT USING (
    auth.uid() = rider_id OR auth.uid() = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "ride_requests_insert" ON public.ride_requests FOR INSERT WITH CHECK (auth.uid() = rider_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "ride_requests_update" ON public.ride_requests FOR UPDATE USING (
    auth.uid() = rider_id OR auth.uid() = driver_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_ride_requests_rider ON public.ride_requests(rider_id);
CREATE INDEX IF NOT EXISTS idx_ride_requests_driver ON public.ride_requests(driver_id);
CREATE INDEX IF NOT EXISTS idx_ride_requests_status ON public.ride_requests(status);

-- ── 8. DRIVER LOCATIONS TABLE (real-time tracking) ─────────────
CREATE TABLE IF NOT EXISTS public.driver_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  lat NUMERIC(10,7) NOT NULL,
  lng NUMERIC(10,7) NOT NULL,
  heading NUMERIC(5,2),
  speed NUMERIC(5,2),
  is_online BOOLEAN DEFAULT false,
  is_on_ride BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "driver_locations_select" ON public.driver_locations FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "driver_locations_update" ON public.driver_locations FOR UPDATE USING (auth.uid() = driver_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_driver_locations_online ON public.driver_locations(is_online) WHERE is_online = true;

-- ── 9. VOLUNTEER SCHEDULES TABLE ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.volunteer_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ministry TEXT NOT NULL,
  role TEXT,
  shift_date DATE NOT NULL,
  start_time TIME,
  end_time TIME,
  status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'confirmed', 'completed', 'cancelled')),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, shift_date, ministry)
);

ALTER TABLE public.volunteer_schedules ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "volunteer_schedules_select" ON public.volunteer_schedules FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role IN ('superadmin', 'employee', 'pastor', 'bishop') OR tenant_id = volunteer_schedules.tenant_id))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "volunteer_schedules_insert" ON public.volunteer_schedules FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_volunteer_schedules_tenant ON public.volunteer_schedules(tenant_id);
CREATE INDEX IF NOT EXISTS idx_volunteer_schedules_date ON public.volunteer_schedules(shift_date);

-- ── 10. WORSHIP LYRICS TABLE ───────────────────────────────────
CREATE TABLE IF NOT EXISTS public.worship_lyrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.tenants(id),
  title TEXT NOT NULL,
  artist TEXT,
  album TEXT,
  lyrics TEXT NOT NULL,
  chords TEXT,
  category TEXT DEFAULT 'praise',
  key_signature TEXT,
  tempo INT,
  is_original BOOLEAN DEFAULT false,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.worship_lyrics ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "worship_lyrics_select" ON public.worship_lyrics FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "worship_lyrics_insert" ON public.worship_lyrics FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'pastor', 'bishop', 'praise_team_leader', 'worship_leader'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_worship_lyrics_tenant ON public.worship_lyrics(tenant_id);
CREATE INDEX IF NOT EXISTS idx_worship_lyrics_category ON public.worship_lyrics(category);

-- ── 11. EVENT RSVP TABLE ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.event_rsvps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'declined', 'attended', 'no_show')),
  guests INT DEFAULT 0,
  notes TEXT,
  checked_in_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(event_id, user_id)
);

ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "event_rsvps_select" ON public.event_rsvps FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public.events WHERE id = event_rsvps.event_id AND (created_by = auth.uid() OR tenant_id IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "event_rsvps_insert" ON public.event_rsvps FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "event_rsvps_update" ON public.event_rsvps FOR UPDATE USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_event_rsvps_event ON public.event_rsvps(event_id);
CREATE INDEX IF NOT EXISTS idx_event_rsvps_user ON public.event_rsvps(user_id);

-- ── 12. ADD IDEMPOTENCY KEY TO LIPILA WEBHOOK ──────────────────
-- This ensures webhook can't process the same event twice
ALTER TABLE IF EXISTS public.coa_payments ADD COLUMN IF NOT EXISTS webhook_idempotency TEXT UNIQUE;

-- ── 13. RATE LIMITING TABLE ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rate_limits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_count INT DEFAULT 1,
  UNIQUE(key, window_start)
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_key ON public.rate_limits(key);

-- ── 14. AUDIT LOG TABLE ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  changes JSONB,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "audit_logs_select" ON public.audit_logs FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "audit_logs_insert" ON public.audit_logs FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_audit_logs_user ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs(created_at DESC);

-- ── 15. ADD MISSING COLUMNS TO EXISTING TABLES ─────────────────
ALTER TABLE IF EXISTS public.events ADD COLUMN IF NOT EXISTS rsvp_enabled BOOLEAN DEFAULT false;
ALTER TABLE IF EXISTS public.events ADD COLUMN IF NOT EXISTS max_attendees INT;
ALTER TABLE IF EXISTS public.events ADD COLUMN IF NOT EXISTS ticket_price NUMERIC(10,2) DEFAULT 0;

ALTER TABLE IF EXISTS public.churches ADD COLUMN IF NOT EXISTS service_times JSONB DEFAULT '[]';
ALTER TABLE IF EXISTS public.churches ADD COLUMN IF NOT EXISTS social_links JSONB DEFAULT '{}';

-- ── 16. ENABLE REALTIME FOR KEY TABLES ─────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- Add tables to realtime for live updates
    FOR tbl IN 
      SELECT unnest(ARRAY['driver_locations', 'ride_requests', 'coa_payments', 'notifications', 'event_rsvps'])
    LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = tbl) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl);
      END IF;
    END LOOP;
  END IF;
END $$;

COMMIT;