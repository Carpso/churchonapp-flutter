-- 20260896 Sermon reactions + streaming fixes
-- 1) sermon_reactions must be in the realtime publication so insight chats
--    and amen reactions update live (streamSermonInsights was dead).
ALTER PUBLICATION supabase_realtime ADD TABLE sermon_reactions;

-- 2) Denormalized reaction counts on sermons (read once, no N+1 per card)
--    + audio_url so audio-only sermons can actually be played.
ALTER TABLE sermons
  ADD COLUMN IF NOT EXISTS amen_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS insight_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS audio_url text;

-- 3) Keep counts in sync whenever a reaction is added or removed.
CREATE OR REPLACE FUNCTION sync_sermon_reaction_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_id uuid;
BEGIN
  target_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.sermon_id ELSE NEW.sermon_id END;
  UPDATE sermons SET
    amen_count    = (SELECT count(*) FROM sermon_reactions r WHERE r.sermon_id = target_id AND r.reaction_type = 'amen'),
    insight_count = (SELECT count(*) FROM sermon_reactions r WHERE r.sermon_id = target_id AND r.reaction_type = 'discuss')
  WHERE id = target_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE EXECUTE ON FUNCTION sync_sermon_reaction_counts() FROM anon, authenticated;

DROP TRIGGER IF EXISTS trg_sync_sermon_reaction_counts ON sermon_reactions;
CREATE TRIGGER trg_sync_sermon_reaction_counts
AFTER INSERT OR DELETE ON sermon_reactions
FOR EACH ROW EXECUTE FUNCTION sync_sermon_reaction_counts();

-- Backfill existing reactions into the counters.
UPDATE sermons s SET
  amen_count    = (SELECT count(*) FROM sermon_reactions r WHERE r.sermon_id = s.id AND r.reaction_type = 'amen'),
  insight_count = (SELECT count(*) FROM sermon_reactions r WHERE r.sermon_id = s.id AND r.reaction_type = 'discuss');

-- 4) RLS hardening: reactions are tenant-scoped data.
--    SELECT was USING(true) — any authenticated user could read every
--    church's reactions. INSERT allowed any user to react to any sermon.
DROP POLICY IF EXISTS "Anyone can view reactions" ON sermon_reactions;
DROP POLICY IF EXISTS "Users can react" ON sermon_reactions;

CREATE POLICY "Reactions tenant scoped select" ON sermon_reactions
  FOR SELECT TO authenticated
  USING (
    tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
    OR EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role IN ('superadmin', 'employee', 'coa_employee')
    )
  );

CREATE POLICY "Users can react" ON sermon_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND tenant_id::text IN (SELECT tenant_id FROM profiles WHERE id = auth.uid())
  );