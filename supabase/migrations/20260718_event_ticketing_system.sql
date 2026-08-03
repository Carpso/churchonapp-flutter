-- Event Ticketing System Enhancement
-- Adds ticket types, quantities, capacity management, and check-in tracking

-- Add ticket_type and ticket_quantity to event_registrations
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS ticket_type TEXT DEFAULT 'General';
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS ticket_quantity INTEGER DEFAULT 1;
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS ticket_code TEXT;
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS checked_in_at TIMESTAMPTZ;
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS checked_in_by UUID REFERENCES profiles(id);

-- Add capacity and ticket type config to events
ALTER TABLE events ADD COLUMN IF NOT EXISTS max_capacity INTEGER;
ALTER TABLE events ADD COLUMN IF NOT EXISTS ticket_types JSONB DEFAULT '[{"name": "General", "price": 0, "capacity": null}]';
ALTER TABLE events ADD COLUMN IF NOT EXISTS early_bird_deadline TIMESTAMPTZ;
ALTER TABLE events ADD COLUMN IF NOT EXISTS early_bird_discount NUMERIC(5,2) DEFAULT 0;

-- Create event_checkins table for scan history
CREATE TABLE IF NOT EXISTS event_checkins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  registration_id UUID NOT NULL REFERENCES event_registrations(id) ON DELETE CASCADE,
  scanned_by UUID NOT NULL REFERENCES profiles(id),
  scanned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  scan_method TEXT NOT NULL DEFAULT 'qr_code', -- qr_code, manual
  device_info TEXT,
  UNIQUE(registration_id)
);

-- Enable RLS
ALTER TABLE event_checkins ENABLE ROW LEVEL SECURITY;

-- RLS policies for event_checkins
DROP POLICY IF EXISTS "Authenticated users can read checkins for their events" ON event_checkins;
CREATE POLICY "Authenticated users can read checkins for their events"
  ON event_checkins FOR SELECT
  USING (
    auth.uid() IN (
      SELECT user_id FROM event_registrations WHERE event_id = event_checkins.event_id
      UNION
      SELECT created_by FROM events WHERE id = event_checkins.event_id
    )
  );

DROP POLICY IF EXISTS "Event organizers can insert checkins" ON event_checkins;
CREATE POLICY "Event organizers can insert checkins"
  ON event_checkins FOR INSERT
  WITH CHECK (
    auth.uid() = scanned_by
  );

DROP POLICY IF EXISTS "Event organizers can update checkins" ON event_checkins;
CREATE POLICY "Event organizers can update checkins"
  ON event_checkins FOR UPDATE
  USING (
    auth.uid() = scanned_by
  );

-- Indexes
CREATE INDEX IF NOT EXISTS idx_event_checkins_event ON event_checkins(event_id);
CREATE INDEX IF NOT EXISTS idx_event_checkins_registration ON event_checkins(registration_id);
CREATE INDEX IF NOT EXISTS idx_event_checkins_scanned_at ON event_checkins(scanned_at);
CREATE INDEX IF NOT EXISTS idx_event_registrations_ticket_code ON event_registrations(ticket_code);
CREATE INDEX IF NOT EXISTS idx_event_registrations_ticket_type ON event_registrations(ticket_type);

-- Function to generate unique ticket code
DROP FUNCTION IF EXISTS generate_ticket_code(UUID, UUID);
CREATE OR REPLACE FUNCTION generate_ticket_code(event_id UUID, user_id UUID)
RETURNS TEXT AS $$
BEGIN
  RETURN 'CHURCH-' || SUBSTRING(event_id::text, 1, 8) || '-' || SUBSTRING(user_id::text, 1, 8) || '-' || FLOOR(RANDOM() * 10000)::text;
END;
$$ LANGUAGE plpgsql;

-- Function to check event capacity
DROP FUNCTION IF EXISTS check_event_capacity(UUID);
CREATE OR REPLACE FUNCTION check_event_capacity(p_event_id UUID)
RETURNS TABLE(can_register BOOLEAN, current_count BIGINT, max_cap INTEGER) AS $$
BEGIN
  RETURN QUERY
  SELECT
    CASE
      WHEN e.max_capacity IS NULL THEN TRUE
      ELSE (SELECT COUNT(*) FROM event_registrations WHERE event_id = p_event_id) < e.max_capacity
    END as can_register,
    (SELECT COUNT(*) FROM event_registrations WHERE event_id = p_event_id) as current_count,
    e.max_capacity as max_cap
  FROM events e WHERE e.id = p_event_id;
END;
$$ LANGUAGE plpgsql;

-- Function to record check-in
DROP FUNCTION IF EXISTS record_event_checkin(UUID, UUID, UUID, TEXT);
CREATE OR REPLACE FUNCTION record_event_checkin(
  p_event_id UUID,
  p_registration_id UUID,
  p_scanned_by UUID,
  p_scan_method TEXT DEFAULT 'qr_code'
)
RETURNS JSONB AS $$
DECLARE
  v_already_checked BOOLEAN;
  v_result JSONB;
BEGIN
  -- Check if already checked in
  SELECT EXISTS(
    SELECT 1 FROM event_checkins WHERE registration_id = p_registration_id
  ) INTO v_already_checked;

  IF v_already_checked THEN
    RETURN '{"success": false, "message": "Already checked in", "status": "duplicate"}';
  END IF;

  -- Record check-in
  INSERT INTO event_checkins (event_id, registration_id, scanned_by, scan_method)
  VALUES (p_event_id, p_registration_id, p_scanned_by, p_scan_method);

  -- Update registration
  UPDATE event_registrations
  SET check_in_status = true, checked_in_at = now(), checked_in_by = p_scanned_by
  WHERE id = p_registration_id;

  RETURN '{"success": true, "message": "Check-in successful", "status": "success"}';
END;
$$ LANGUAGE plpgsql;

-- Function to get event check-in stats
DROP FUNCTION IF EXISTS get_event_checkin_stats(UUID);
CREATE OR REPLACE FUNCTION get_event_checkin_stats(p_event_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_total INTEGER;
  v_checked_in INTEGER;
  v_capacity INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_total FROM event_registrations WHERE event_id = p_event_id;
  SELECT COUNT(*) INTO v_checked_in FROM event_checkins WHERE event_id = p_event_id;
  SELECT max_capacity INTO v_capacity FROM events WHERE id = p_event_id;

  RETURN jsonb_build_object(
    'total_registered', v_total,
    'checked_in', v_checked_in,
    'remaining', v_total - v_checked_in,
    'capacity', v_capacity,
    'at_capacity', CASE WHEN v_capacity IS NOT NULL THEN v_total >= v_capacity ELSE FALSE END
  );
END;
$$ LANGUAGE plpgsql;
