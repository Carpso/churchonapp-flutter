-- 20260891_platform_accounts_social_fixes.sql
-- 1) Backfill social post comment counts
-- 2) Protect platform accounts (superadmin + designated COA employee) from demotion/deletion
-- 3) Promote godfreymoseskalambo@gmail.com to coa_employee
-- 4) Complete Rock Of Ages Chapel Kabulonga onboarding (trial + verified + tenant code)

-- ── 1. Backfill comment counts ──────────────────────────────────────────────
UPDATE social_posts p
SET comments_count = (
  SELECT count(*) FROM social_comments c WHERE c.post_id = p.id
)
WHERE comments_count <> (
  SELECT count(*) FROM social_comments c WHERE c.post_id = p.id
);

-- ── 2. Platform account guards ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.protect_platform_accounts()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Deletion of platform accounts is never allowed
  IF TG_OP = 'DELETE' THEN
    IF OLD.role = 'superadmin'
       OR OLD.id = '18dbaf98-ff37-4a0d-8fd4-bf3d592c40da'::uuid THEN
      RAISE EXCEPTION 'Platform accounts are permanent and cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;
  -- The platform superadmin keeps role 'superadmin' forever
  IF OLD.role = 'superadmin' AND NEW.role IS DISTINCT FROM 'superadmin' THEN
    RAISE EXCEPTION 'Superadmin role is permanent and cannot be changed';
  END IF;
  -- The designated COA employee keeps role 'coa_employee' forever
  IF OLD.id = '18dbaf98-ff37-4a0d-8fd4-bf3d592c40da'::uuid
     AND NEW.role IS DISTINCT FROM 'coa_employee' THEN
    RAISE EXCEPTION 'COA employee role is permanent and cannot be changed';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_platform_accounts ON public.profiles;
CREATE TRIGGER trg_protect_platform_accounts
  BEFORE UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_platform_accounts();

-- ── 3. Promote the COA employee account ─────────────────────────────────────
-- The migration runs as postgres (auth.uid() is NULL), so temporarily disable
-- the role-change guard and the audit/notify AFTER triggers; the app_metadata
-- sync trigger stays enabled so the JWT claim follows profiles.role.
ALTER TABLE public.profiles DISABLE TRIGGER trg_profiles_role_change;
ALTER TABLE public.profiles DISABLE TRIGGER trg_log_role_change;
ALTER TABLE public.profiles DISABLE TRIGGER trg_notify_profile_role_change;
UPDATE profiles
SET role = 'coa_employee'
WHERE id = '18dbaf98-ff37-4a0d-8fd4-bf3d592c40da'::uuid
  AND role = 'member';
ALTER TABLE public.profiles ENABLE TRIGGER trg_profiles_role_change;
ALTER TABLE public.profiles ENABLE TRIGGER trg_log_role_change;
ALTER TABLE public.profiles ENABLE TRIGGER trg_notify_profile_role_change;

-- ── 4. Rock Of Ages Chapel Kabulonga: complete onboarding ───────────────────
-- Active 30-day trial (like every other registered church), verified flag
-- with timestamp, and a registered tenant code.
UPDATE churches
SET verified_at         = COALESCE(verified_at, now()),
    trial_started_at    = COALESCE(trial_started_at, now()),
    trial_ends_at       = now() + interval '30 days',
    subscription_ends_at = now() + interval '30 days',
    subscription_status = 'trial'
WHERE id = 'a7d7ef90-5555-4444-9999-d8c9735d4b53';

UPDATE tenants
SET tenant_code = COALESCE(tenant_code, 'COA-ZM_T_' || next_id_sequence('tenant_code'))
WHERE id = 'a7d7ef90-5555-4444-9999-d8c9735d4b53';