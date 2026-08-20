-- 20260926: Carpso inDrive-style negotiation + ministries RLS + Bible reference backfill

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Negotiation columns on ride_requests + delivery_requests
--    negotiation_round: monotonic counter so clients can dedupe dialogs per
--    offer (NOT by fare value — two counters for the same amount were missed).
--    last_offer_by / proposal_expires_at: who owns the open offer + expiry.
--    cancelled_at / cancelled_by: passenger/sender cancels a pending request.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS negotiation_round INT NOT NULL DEFAULT 0;
ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS last_offer_by UUID;
ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS proposal_expires_at TIMESTAMPTZ;
ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
ALTER TABLE ride_requests ADD COLUMN IF NOT EXISTS cancelled_by UUID;

ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS negotiation_round INT NOT NULL DEFAULT 0;
ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS last_offer_by UUID;
ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS proposal_expires_at TIMESTAMPTZ;
ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
ALTER TABLE delivery_requests ADD COLUMN IF NOT EXISTS cancelled_by UUID;

-- negotiation_status now also supports 'passenger_countered' (rider re-counters
-- the driver's offer — inDrive-style back-and-forth).
ALTER TABLE ride_requests DROP CONSTRAINT IF EXISTS ride_requests_negotiation_status_check;
ALTER TABLE ride_requests ADD CONSTRAINT ride_requests_negotiation_status_check
  CHECK (negotiation_status IN ('none','passenger_offered','driver_countered','passenger_countered','accepted'));

ALTER TABLE delivery_requests DROP CONSTRAINT IF EXISTS delivery_requests_negotiation_status_check;
ALTER TABLE delivery_requests ADD CONSTRAINT delivery_requests_negotiation_status_check
  CHECK (negotiation_status IN ('none','passenger_offered','driver_countered','passenger_countered','accepted'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RLS: drivers may negotiate/counter/accept PENDING requests
--    ROOT CAUSE of dead negotiation: pending rows have driver_id = NULL, so the
--    existing UPDATE policies (auth.uid() = driver_id) rejected every driver
--    write — driver counters silently failed with "permission denied".
--    Drivers may only touch rows still pending (status guard), which keeps the
--    atomic accept (WHERE status='pending') race-safe.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "Drivers can negotiate pending ride requests"
  ON ride_requests FOR UPDATE
  USING (
    status = 'pending'
    AND EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'driver')
  );

CREATE POLICY "Drivers can negotiate pending delivery requests"
  ON delivery_requests FOR UPDATE
  USING (
    status = 'pending'
    AND EXISTS (SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'driver')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Ministries RLS fixes
--    (a) Members could never leave a ministry — no DELETE policy for their own
--        membership row. Added.
--    (b) "Tenant admins can manage ministries" referenced role 'employee'
--        (renamed to 'coa_employee' in data) and cast profiles.tenant_id::uuid
--        (text column) — platform staff therefore had no access. Recreated with
--        coa_employee + text compare + platform-staff bypass.
--    (c) "Ministry leaders can manage members" now also lets platform staff in.
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can leave ministries" ON ministry_members;
CREATE POLICY "Users can leave ministries"
  ON ministry_members FOR DELETE
  USING (auth.uid() = profile_id);

DROP POLICY IF EXISTS "Tenant admins can manage ministries" ON ministries;
CREATE POLICY "Tenant admins can manage ministries"
  ON ministries FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND (
          p.role IN ('superadmin','coa_employee','employee')
          OR (
            p.tenant_id = ministries.tenant_id::text
            AND p.role IN ('admin','pastor','bishop','apostle','general_secretary','general_treasurer')
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid()
        AND (
          p.role IN ('superadmin','coa_employee','employee')
          OR (
            p.tenant_id = ministries.tenant_id::text
            AND p.role IN ('admin','pastor','bishop','apostle','general_secretary','general_treasurer')
          )
        )
    )
  );

DROP POLICY IF EXISTS "Ministry leaders can manage members" ON ministry_members;
CREATE POLICY "Ministry leaders can manage members"
  ON ministry_members FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM ministries m
      WHERE m.id = ministry_members.ministry_id AND m.leader_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role IN ('superadmin','coa_employee','employee')
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Bible: backfill verse reference strings (scripture search + share depend
--    on bible_verses.reference, which was NULL for all seeded rows).
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE bible_verses v
SET reference = b.abbreviation || ' ' || v.chapter || ':' || v.verse
FROM bible_books b
WHERE v.reference IS NULL AND b.id = v.book_id;

UPDATE bible_verses v
SET search_vector = to_tsvector('simple', COALESCE(v.reference, '') || ' ' || v.text)
WHERE v.search_vector IS NULL AND v.reference IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Tunable: how long a fare proposal stays open before it lapses.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO platform_settings (key, value)
VALUES ('ride_negotiation_timeout_sec', '120')
ON CONFLICT (key) DO NOTHING;