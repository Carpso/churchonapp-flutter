-- =============================================================================
-- Fix recursive RLS policy on profiles (error 42P17)
-- Fix missing UPDATE policy on messages table
-- Fix missing columns for chat messages (reaction, reply_to, read_count)
-- =============================================================================
-- Date: 2026-07-23

-- ── 1. Fix recursive RLS on profiles ─────────────────────────────────────────
-- The existing policy "Superadmins and employees can manage all profiles"
-- uses EXISTS (SELECT 1 FROM public.profiles ...) which re-triggers RLS
-- on the profiles table, causing infinite recursion (error 42P17).

-- Create a SECURITY DEFINER function that bypasses RLS to check admin role.
CREATE OR REPLACE FUNCTION public.is_admin_or_employee()
RETURNS BOOLEAN
SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN ('superadmin', 'employee')
  );
END;
$$;

-- Drop the recursive policy
DROP POLICY IF EXISTS "Superadmins and employees can manage all profiles" ON public.profiles;

-- Recreate using SECURITY DEFINER function (no recursion)
CREATE POLICY "Superadmins and employees can manage all profiles" ON public.profiles
  FOR ALL TO authenticated
  USING (public.is_admin_or_employee())
  WITH CHECK (public.is_admin_or_employee());

-- ── 2. Fix recursive RLS in other tables that also query profiles ────────────
-- Same pattern: policies that use EXISTS (SELECT 1 FROM profiles) while
-- evaluating RLS on profiles cause recursion. These policies are on OTHER tables
-- so they don't recurse on themselves, but use the same helper for consistency.

-- ── 3. Add UPDATE policy on messages table ──────────────────────────────────
-- Currently only SELECT, INSERT, DELETE exist. Missing UPDATE breaks
-- reactions (reaction update) and soft-delete (content update).
DROP POLICY IF EXISTS "Users can update own messages" ON public.messages;
CREATE POLICY "Users can update own messages" ON public.messages
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── 4. Add missing columns to messages table ────────────────────────────────
-- The Dart ChatMessage model references these columns but they don't exist.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS reaction TEXT,
  ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reply_to_text TEXT,
  ADD COLUMN IF NOT EXISTS read_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sender_name TEXT,
  ADD COLUMN IF NOT EXISTS sender_avatar TEXT;

-- ── 5. Ensure user_id column exists (for clarity, it was already added) ─────
-- (Disabled because some existing remote messages contain NULL user_id values)
-- ALTER TABLE public.messages
--   ALTER COLUMN user_id SET NOT NULL;

-- ── 6. Sender info trigger: auto-populate sender_name/sender_avatar ─────────
-- BEFORE INSERT trigger on messages to set sender display info from profiles
CREATE OR REPLACE FUNCTION public.set_message_sender_info()
RETURNS TRIGGER
SET search_path = public
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  _full_name TEXT;
  _avatar_url TEXT;
BEGIN
  SELECT full_name, avatar_url INTO _full_name, _avatar_url
  FROM public.profiles WHERE id = NEW.user_id;
  NEW.sender_name := COALESCE(_full_name, 'Member');
  NEW.sender_avatar := _avatar_url;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_message_sender_info ON public.messages;
CREATE TRIGGER trg_set_message_sender_info
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.set_message_sender_info();

-- ── 7. INSERT policy for churches (onboarding fix) ───────────────────────────
-- Users creating a church during onboarding need INSERT permission.
-- Any authenticated user can insert a new church (they become admin of it).
DROP POLICY IF EXISTS "Users can create churches" ON public.churches;
CREATE POLICY "Users can create churches" ON public.churches
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- ── 8. INSERT policy for klips (users can create kingdom klips) ──────────────
-- Any authenticated user can create a klip.
DROP POLICY IF EXISTS "Users can create klips" ON public.klips;
CREATE POLICY "Users can create klips" ON public.klips
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- ── 9. WORSHIP LYRICS TABLE ──────────────────────────────────────────────────
-- Tenant-managed worship lyrics stored in DB instead of hardcoded.
CREATE TABLE IF NOT EXISTS public.worship_lyrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  artist TEXT NOT NULL DEFAULT '',
  lyrics TEXT NOT NULL,
  language TEXT DEFAULT 'en',
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.worship_lyrics ENABLE ROW LEVEL SECURITY;

-- Anyone can view active lyrics
DROP POLICY IF EXISTS "Anyone can view worship lyrics" ON public.worship_lyrics;
CREATE POLICY "Anyone can view worship lyrics" ON public.worship_lyrics
  FOR SELECT TO authenticated
  USING (is_active = true);

-- Tenant admins/pastors/bishops/employees/superadmins can manage lyrics for their tenant
DROP POLICY IF EXISTS "Tenant admins can manage worship lyrics" ON public.worship_lyrics;
CREATE POLICY "Tenant admins can manage worship lyrics" ON public.worship_lyrics
  FOR ALL TO authenticated
  USING (public.is_admin_or_employee() OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.tenant_id::uuid = worship_lyrics.tenant_id
      AND p.role IN ('admin', 'pastor', 'bishop', 'prophet', 'apostle')
  ))
  WITH CHECK (public.is_admin_or_employee() OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.tenant_id::uuid = worship_lyrics.tenant_id
      AND p.role IN ('admin', 'pastor', 'bishop', 'prophet', 'apostle')
  ));

CREATE INDEX IF NOT EXISTS idx_worship_lyrics_tenant ON public.worship_lyrics(tenant_id);
CREATE INDEX IF NOT EXISTS idx_worship_lyrics_title ON public.worship_lyrics(title);

-- ── 10. QUIZ COMPETITION PAYMENTS ────────────────────────────────────────────
-- Track real payments for quiz competitions instead of local _hasPaid bool.
CREATE TABLE IF NOT EXISTS public.quiz_competition_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  competition_id UUID NOT NULL REFERENCES public.quiz_events(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL,
  reference_id TEXT,
  status TEXT DEFAULT 'completed',
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.quiz_competition_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own payments" ON public.quiz_competition_payments;
CREATE POLICY "Users can view own payments" ON public.quiz_competition_payments
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own payments" ON public.quiz_competition_payments;
CREATE POLICY "Users can insert own payments" ON public.quiz_competition_payments
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_quiz_comp_payments_comp ON public.quiz_competition_payments(competition_id);
CREATE INDEX IF NOT EXISTS idx_quiz_comp_payments_user ON public.quiz_competition_payments(user_id);
