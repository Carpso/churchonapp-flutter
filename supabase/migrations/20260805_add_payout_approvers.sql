-- Real-money payout approval is restricted to the Superadmin.
-- A Superadmin may elevate specific COA employees to also approve payouts.
-- Only superadmins can grant/revoke approver rights (no recursion: policy queries
-- public.profiles, not this table).

CREATE TABLE IF NOT EXISTS public.payout_approvers (
  approver_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_by  UUID REFERENCES auth.users(id),
  created_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.payout_approvers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Superadmins manage payout approvers" ON public.payout_approvers;
CREATE POLICY "Superadmins manage payout approvers" ON public.payout_approvers
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'superadmin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'superadmin'
    )
  );
