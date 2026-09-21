-- ============================================================================
-- 20261208_klips_is_audio_and_post_policy.sql
-- Klips: make posting + feed reliable end-to-end.
--
-- ROOT CAUSES (verified against the live database):
--   1. `kingdom_klips_screen._fetchKlips()` SELECTs `klips.is_audio`, but the
--      column DID NOT EXIST -> PostgREST 42703 -> the whole query failed and the
--      catch returned `[]`, so the Klips feed was permanently empty (a SILENT
--      failure). A klip that DID insert never appeared, which reads as
--      "posting a Klip fails".
--   2. The table-level INSERT policy was fine (`auth.uid() = user_id`), but we
--      add an explicit leadership-inclusive policy so a future role-gated
--      policy can never lock out `leader` / `coa_employee` / `department_leader`
--      (permissive policies are OR-ed, so this only ever ADDS access).
-- ============================================================================

-- 1) The column the feed + player already reference.
ALTER TABLE public.klips ADD COLUMN IF NOT EXISTS is_audio boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.klips.is_audio IS
  'True when the klip is an audio-only clip (rendered with the audio player).';

-- 2) Defensive, leadership-inclusive INSERT policy. Permissive -> OR-ed with the
--    existing "Authenticated users can create klips" / "Users can create klips".
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'klips'
      AND policyname = 'Church leaders can create klips'
  ) THEN
    CREATE POLICY "Church leaders can create klips" ON public.klips
      FOR INSERT TO authenticated
      WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (
          SELECT 1 FROM public.profiles p
          WHERE p.id = auth.uid()
            AND (
              p.role IN (
                'superadmin','super_admin','coa_employee','employee',
                'pastor','bishop','apostle','prophet','general_secretary',
                'general_treasurer','treasurer','admin','leader',
                'department_leader','worship_leader','praise_team_leader'
              )
            )
        )
      );
  END IF;
END $$;

-- Keep the public read surface explicit for the new column.
GRANT SELECT (is_audio) ON public.klips TO anon, authenticated;
