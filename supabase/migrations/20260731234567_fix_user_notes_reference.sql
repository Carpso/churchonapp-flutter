-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX USER NOTES REFERENCE
-- Adds reference_id column so sermon notes and other features can associate
-- notes with specific entities (sermons, events, etc.) without needing
-- separate FK columns for each feature.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Add reference_id for associating notes with any entity (sermon, event, etc.)
ALTER TABLE IF EXISTS public.user_notes
  ADD COLUMN IF NOT EXISTS reference_id TEXT;

-- Add index for fast lookups by user + reference
CREATE INDEX IF NOT EXISTS idx_user_notes_user_reference
  ON public.user_notes(user_id, reference_id);

-- Add index for reference_id lookups
CREATE INDEX IF NOT EXISTS idx_user_notes_reference
  ON public.user_notes(reference_id);
