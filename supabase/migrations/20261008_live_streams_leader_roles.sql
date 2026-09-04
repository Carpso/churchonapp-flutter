-- 20261008 — Widen live_streams INSERT/ALL policy so ALL leadership roles that
-- can start a stream (per Edge Function + GoRouter) can also insert the stream
-- row. Previously only superadmin/coa_employee/pastor/bishop/admin were allowed
-- by the WITH CHECK, so apostle/prophet/general_secretary/leader/department_leader
-- got an RLS error when starting ("Streaming unavailable").

DROP POLICY IF EXISTS "live_streams_manage" ON public.live_streams;

CREATE POLICY "live_streams_manage"
  ON public.live_streams FOR ALL
  TO authenticated
  USING (
    church_id::text IN (
      SELECT tenant_id FROM profiles WHERE id = auth.uid()
      AND role IN (
        'superadmin', 'coa_employee', 'pastor', 'bishop', 'admin',
        'apostle', 'prophet', 'general_secretary', 'leader', 'department_leader',
        'general_treasurer'
      )
    )
    OR EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid()
      AND role IN ('superadmin', 'coa_employee')
    )
  )
  WITH CHECK (
    church_id::text IN (
      SELECT tenant_id FROM profiles WHERE id = auth.uid()
      AND role IN (
        'superadmin', 'coa_employee', 'pastor', 'bishop', 'admin',
        'apostle', 'prophet', 'general_secretary', 'leader', 'department_leader',
        'general_treasurer'
      )
    )
    OR EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid()
      AND role IN ('superadmin', 'coa_employee')
    )
  );
