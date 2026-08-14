-- ═══════════════════════════════════════════════════════════════════════════════
-- 20260891: ONBOARDING, GROUP GIVING, KIDS AUDIO + DRIVER FIXES
--  1. check_role_change_permission: allow SELF-SERVICE onboarding roles
--     (driver / bookshop_owner / vendor) + server-side bookshop_owner assignment.
--  2. ride_registrations: dedupe + UNIQUE(user_id) so ON CONFLICT works.
--  3. Group giving RLS: replace broken tenant_id::uuid casts (profiles.tenant_id
--     is TEXT → 22P02 / empty results) with text-safe comparisons.
--  4. Add fundraising tables to supabase_realtime so group giving streams live.
--  5. Kids zone audio: swap 5 multi-chapter KJV range files for per-chapter
--     TTS files that actually start at the right story.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. ROLE-CHANGE TRIGGER: allow self-service onboarding + bookshop assignment
CREATE OR REPLACE FUNCTION public.check_role_change_permission()
RETURNS TRIGGER
SET search_path = public, auth
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  superadmin_count INT;
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    -- Self-service onboarding roles: a user may apply for these on their own
    IF NEW.role IN ('driver', 'bookshop_owner', 'vendor') AND OLD.id = auth.uid() THEN
      RETURN NEW;
    END IF;

    -- Server-side assignment (Edge Function / service role): allow the
    -- bookshop_owner role only when the new tenant is actually a bookshop
    IF NEW.role = 'bookshop_owner' AND NEW.tenant_id IS NOT NULL
       AND EXISTS (
         SELECT 1 FROM public.tenants t
         WHERE t.id::text = NEW.tenant_id::text AND t.type = 'bookshop'
       ) THEN
      RETURN NEW;
    END IF;

    -- Check actor has permission
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND (role = 'superadmin' OR role = 'employee')
    ) THEN
      RAISE EXCEPTION 'Only superadmins and employees can change roles';
    END IF;

    -- Last-superadmin guard: prevent demoting the only superadmin
    IF OLD.role = 'superadmin' AND NEW.role != 'superadmin' THEN
      SELECT count(*) INTO superadmin_count
      FROM public.profiles
      WHERE role = 'superadmin';

      IF superadmin_count <= 1 THEN
        RAISE EXCEPTION 'Cannot demote the last superadmin. Promote another user first.';
      END IF;
    END IF;

    -- Self-demotion guard: prevent changing your own role
    IF OLD.id = auth.uid() THEN
      RAISE EXCEPTION 'You cannot change your own role.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 2. ride_registrations: unique user_id (fixes ON CONFLICT 42P10 everywhere)
DELETE FROM public.ride_registrations a
USING public.ride_registrations b
WHERE a.user_id = b.user_id AND a.id <> b.id AND a.updated_at < b.updated_at;

CREATE UNIQUE INDEX IF NOT EXISTS ride_registrations_user_id_key
  ON public.ride_registrations (user_id);

-- 3. GROUP GIVING RLS: text-safe tenant comparisons (profiles.tenant_id is TEXT)

-- 3a. group_contributions SELECT
DROP POLICY IF EXISTS "Tenant members can view group contributions" ON public.group_contributions;
CREATE POLICY "Tenant members can view group contributions"
  ON public.group_contributions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.tenant_id IS NOT NULL
        AND p.tenant_id = group_contributions.tenant_id::text
    )
  );

-- 3b. group_contributions INSERT (tenant admins)
DROP POLICY IF EXISTS "Tenant admins can create group contributions" ON public.group_contributions;
CREATE POLICY "Tenant admins can create group contributions"
  ON public.group_contributions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND (p.role IN ('superadmin', 'admin', 'pastor', 'bishop'))
        AND p.tenant_id IS NOT NULL
        AND p.tenant_id = group_contributions.tenant_id::text
    )
  );

-- 3c. fundraising_ventures SELECT (also reads other tenants' active ventures)
DROP POLICY IF EXISTS "Anyone can view active ventures" ON public.fundraising_ventures;
CREATE POLICY "Anyone can view active ventures"
  ON public.fundraising_ventures FOR SELECT
  USING (
    status = 'active' OR
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.tenant_id IS NOT NULL
        AND p.tenant_id = fundraising_ventures.tenant_id::text
    )
  );

-- 3d. fundraising_invites SELECT
DROP POLICY IF EXISTS "Tenants can view their invites" ON public.fundraising_invites;
CREATE POLICY "Tenants can view their invites"
  ON public.fundraising_invites FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.tenant_id IS NOT NULL AND (
        p.tenant_id = fundraising_invites.to_tenant_id::text OR
        p.tenant_id = fundraising_invites.from_tenant_id::text
      )
    )
  );

-- 4. REAL-TIME PUBLICATION: group giving + fundraising tables stream live
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.group_contributions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.group_contribution_members;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.group_contribution_payments;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.fundraising_ventures;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.fundraising_contributions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 5. KIDS ZONE AUDIO: replace multi-chapter KJV range files with per-chapter
--    TTS files that start at the correct story chapter
UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/audio/kjv/Genesis/006.mp3'
WHERE title = 'Noah and the Ark';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/audio/kjv/Luke/002.mp3'
WHERE title = 'The Birth of Jesus';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/audio/kjv/Luke/010.mp3'
WHERE title = 'The Good Samaritan';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/audio/kjv/Luke/015.mp3'
WHERE title = 'The Prodigal Son';

UPDATE public.kids_zone_resources
SET content_url = 'https://media.churchonapp.com/audio/kjv/John/006.mp3'
WHERE title = 'Jesus Feeds 5000';