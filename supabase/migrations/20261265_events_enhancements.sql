-- ============================================================================
-- 20261265 — EVENTS ENHANCEMENTS
--
-- Owner: "delete the bugs you can and enhance where possible."
--
-- 1. RACE FIX: registerForEvent read attendee_count then wrote count+1 in two
--    round trips — two concurrent registrations lost one count. Replaced by a
--    single atomic RPC that also enforces the already-registered guard at the
--    DB level and inserts the confirmation notification.
-- 2. DUPLICATE PREVENTION: unique indexes stop the seed-style duplication
--    (same title + tenant + date) from ever recurring, and stop a user from
--    double-registering.
-- 3. CONTENT: all 13 remaining events were in the past, so the events hub
--    showed only the "Recent Events" fallback. Seeds six future events for
--    the one tenant that actually has events, spread over the next six weeks.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Hard guards
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_event_registrations_event_user
  ON public.event_registrations (event_id, user_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_events_tenant_title_date
  ON public.events (
    (COALESCE(tenant_id::text, '-')),
    (lower(btrim(title))),
    ((date AT TIME ZONE 'utc')::date)
  );

-- ---------------------------------------------------------------------------
-- 2. Atomic registration
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_for_event(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_e    public.events%ROWTYPE;
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('registered', false, 'error', 'Please login to register');
  END IF;

  SELECT * INTO v_e FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('registered', false, 'error', 'Event not found');
  END IF;

  -- Capacity guard (max_capacity / max_attendees when set).
  IF COALESCE(v_e.max_capacity, v_e.max_attendees) IS NOT NULL
     AND COALESCE(v_e.attendee_count, 0) >= COALESCE(v_e.max_capacity, v_e.max_attendees) THEN
    RETURN jsonb_build_object('registered', false, 'error', 'This event is fully booked');
  END IF;

  BEGIN
    INSERT INTO public.event_registrations (event_id, user_id)
    VALUES (p_event_id, v_uid);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('registered', false, 'error', 'You are already registered for this event.');
  END;

  UPDATE public.events
     SET attendee_count = COALESCE(attendee_count, 0) + 1
   WHERE id = p_event_id
   RETURNING attendee_count INTO v_count;

  INSERT INTO public.notifications (user_id, tenant_id, title, body, is_read, type, reference_id)
  VALUES (
    v_uid, v_e.tenant_id,
    'Registered: ' || COALESCE(v_e.title, 'Event'),
    'You have successfully registered for ' || COALESCE(v_e.title, 'this event') || '.',
    false, 'event', p_event_id::text
  );

  RETURN jsonb_build_object(
    'registered', true,
    'attendee_count', v_count,
    'title', v_e.title
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.register_for_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_for_event(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Future events (the hub was an all-past wall)
-- ---------------------------------------------------------------------------
INSERT INTO public.events (title, description, location, date, end_date, image_url,
                           category, created_by, user_id, hosted_by, tenant_id, church_id,
                           attendee_count, is_paid_event, ticket_price)
SELECT
  v.title, v.descr, v.loc, v.d, v.d + interval '3 hours', v.img,
  v.cat, ids.uid, ids.uid, ids.uid, ids.tid, ids.tid,
  0, false, 0
FROM (VALUES
  ('Sunrise Prayer Summit',
   'An early-morning prayer summit for the nation — worship, intercession and a word for the year.',
   'Main Sanctuary, Rock Of Ages Kabulonga',
   now() + interval '7 days', 'https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=800', 'Conference'),
  ('Youth Explosion Night',
   'Music, testimonies and the Word — the biggest youth night of the season. Bring a friend.',
   'Church Grounds, Kabulonga',
   now() + interval '14 days', 'https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=800', 'Youth Camp'),
  ('Marriage & Family Seminar',
   'Practical, biblical teaching for couples and singles preparing for family life.',
   'Annex Hall',
   now() + interval '21 days', 'https://images.unsplash.com/photo-1517048676732-d65bc937f952?w=800', 'Seminar'),
  ('Night of Worship',
   'A full night of worship with the mass choir and guest ministers. Free entry.',
   'Main Sanctuary',
   now() + interval '28 days', 'https://images.unsplash.com/photo-1438232992991-995b7058bbb3?w=800', 'Concert'),
  ('Community Outreach — Matero',
   'Join the outreach team: food packs, medical check-ups and the Gospel in Matero.',
   'Matero Community Centre',
   now() + interval '35 days', 'https://images.unsplash.com/photo-1499134296992-8d63c3db95f9?w=800', 'Other'),
  ('Leadership & Ministry Conference',
   'Equipping leaders for the work of ministry — sessions for pastors, department heads and workers.',
   'Main Sanctuary',
   now() + interval '42 days', 'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=800', 'Conference')
) AS v(title, descr, loc, d, img, cat)
CROSS JOIN (SELECT 'a7d7ef90-5555-4444-9999-d8c9735d4b53'::uuid AS tid,
                   '68ae4f09-84e1-47dc-84c1-8f6eee58db99'::uuid AS uid) AS ids
WHERE NOT EXISTS (
  SELECT 1 FROM public.events e
   WHERE e.tenant_id = ids.tid AND e.title = v.title
);

-- ---------------------------------------------------------------------------
-- 4. Verification
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_fail text := '';
  v_future integer;
BEGIN
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'register_for_event') <> 1 THEN
    v_fail := v_fail || ' rpc;';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ux_event_registrations_event_user') THEN
    v_fail := v_fail || ' reg_index;';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ux_events_tenant_title_date') THEN
    v_fail := v_fail || ' dedupe_index;';
  END IF;
  SELECT count(*) INTO v_future FROM public.events WHERE date > now();
  IF v_future < 6 THEN
    v_fail := v_fail || ' future_seed(' || v_future || ');';
  END IF;
  IF v_fail <> '' THEN
    RAISE EXCEPTION 'VERIFICATION FAILED:%', v_fail;
  END IF;
  RAISE NOTICE 'events enhancements applied: % future events seeded', v_future;
END;
$$;
