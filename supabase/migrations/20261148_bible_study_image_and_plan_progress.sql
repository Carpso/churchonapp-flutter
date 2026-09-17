-- ============================================================================
-- 20261148_bible_study_image_and_plan_progress.sql
-- 1. Bible studies: cover image (the schedule list had no pictures).
-- 2. Reading plans: PER-ENTRY completion (the only progress stored before was a
--    coarse `completed_days` counter, so verses could not be "ticked").
-- ============================================================================

ALTER TABLE public.bible_studies ADD COLUMN IF NOT EXISTS image_url text;

CREATE TABLE IF NOT EXISTS public.reading_plan_entry_progress (
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  entry_id     uuid NOT NULL REFERENCES public.reading_plan_entries(id) ON DELETE CASCADE,
  plan_id      uuid,
  completed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, entry_id)
);

CREATE INDEX IF NOT EXISTS idx_rpep_user_plan
  ON public.reading_plan_entry_progress (user_id, plan_id);

ALTER TABLE public.reading_plan_entry_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rpep_own_all" ON public.reading_plan_entry_progress;
CREATE POLICY "rpep_own_all" ON public.reading_plan_entry_progress
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Toggle one reading-plan entry (verse/passage) done/undone for the caller.
CREATE OR REPLACE FUNCTION public.toggle_reading_plan_entry(
  p_entry_id uuid,
  p_done     boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_plan uuid;
  v_n    int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;

  SELECT plan_id INTO v_plan FROM public.reading_plan_entries WHERE id = p_entry_id;
  IF v_plan IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'entry_not_found');
  END IF;

  IF p_done THEN
    INSERT INTO public.reading_plan_entry_progress (user_id, entry_id, plan_id)
    VALUES (v_uid, p_entry_id, v_plan)
    ON CONFLICT (user_id, entry_id) DO NOTHING;
  ELSE
    DELETE FROM public.reading_plan_entry_progress
     WHERE user_id = v_uid AND entry_id = p_entry_id;
  END IF;

  SELECT count(*) INTO v_n
    FROM public.reading_plan_entry_progress
   WHERE user_id = v_uid AND plan_id = v_plan;

  RETURN jsonb_build_object('ok', true, 'completed', v_n);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.toggle_reading_plan_entry(uuid, boolean) FROM anon;
REVOKE EXECUTE ON FUNCTION public.toggle_reading_plan_entry(uuid, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.toggle_reading_plan_entry(uuid, boolean) TO authenticated;

-- Completed entry ids for a plan + the caller (drives the tick UI).
CREATE OR REPLACE FUNCTION public.get_reading_plan_completed(p_plan_id uuid)
RETURNS TABLE (entry_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT entry_id
    FROM public.reading_plan_entry_progress
   WHERE user_id = auth.uid() AND plan_id = p_plan_id;
$$;

REVOKE EXECUTE ON FUNCTION public.get_reading_plan_completed(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_reading_plan_completed(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.get_reading_plan_completed(uuid) TO authenticated;
