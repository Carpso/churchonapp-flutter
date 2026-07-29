-- =====================================================
-- Infinite Bible Question Pipeline & Tournament Scale
-- =====================================================

-- 1. Add question_hash for deduplication (NULL allowed for existing rows)
ALTER TABLE public.quiz_questions ADD COLUMN IF NOT EXISTS question_hash TEXT;

-- Create unique index (not constraint) so existing duplicates don't break migration
-- Existing rows with NULL hash are allowed; new inserts must provide a hash
CREATE UNIQUE INDEX IF NOT EXISTS idx_quiz_questions_hash_unique
  ON public.quiz_questions (question_hash)
  WHERE question_hash IS NOT NULL;

-- Add AI generation flag
ALTER TABLE public.quiz_questions ADD COLUMN IF NOT EXISTS ai_generated BOOLEAN NOT NULL DEFAULT false;

-- Add generator batch ID (which batch produced this question)
ALTER TABLE public.quiz_questions ADD COLUMN IF NOT EXISTS generator_batch_id TEXT;

-- Add scripture_ref alias column (maps from scripture_reference for clarity)
-- NOTE: scripture_reference already exists. This migration does NOT rename it.
-- New questions use scripture_reference; the Flutter model uses scriptureReference.

-- Indexes for batch generation queries
CREATE INDEX IF NOT EXISTS idx_quiz_questions_ai_generated
  ON public.quiz_questions (ai_generated);

CREATE INDEX IF NOT EXISTS idx_quiz_questions_category_difficulty
  ON public.quiz_questions (category, difficulty);

-- =====================================================
-- 2. User Answered Questions — tracks per-user history
-- =====================================================

CREATE TABLE IF NOT EXISTS public.user_answered_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES public.quiz_questions(id) ON DELETE CASCADE,
  match_id UUID REFERENCES public.pvp_matches(id) ON DELETE SET NULL,
  event_id UUID REFERENCES public.quiz_events(id) ON DELETE SET NULL,
  is_correct BOOLEAN NOT NULL DEFAULT false,
  response_time_ms INT NOT NULL DEFAULT 0,
  answered_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prevent duplicate answers per user per question per context (same match or event)
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_answered_question_unique
  ON public.user_answered_questions (user_id, question_id, COALESCE(match_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Indexes for dedup queries
CREATE INDEX IF NOT EXISTS idx_user_answered_user_id
  ON public.user_answered_questions (user_id);

CREATE INDEX IF NOT EXISTS idx_user_answered_question_id
  ON public.user_answered_questions (question_id);

-- =====================================================
-- 3. RLS policies for user_answered_questions
-- =====================================================

ALTER TABLE public.user_answered_questions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_answered_select_own" ON public.user_answered_questions;
CREATE POLICY "user_answered_select_own"
  ON public.user_answered_questions FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "user_answered_insert_own" ON public.user_answered_questions;
CREATE POLICY "user_answered_insert_own"
  ON public.user_answered_questions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- =====================================================
-- 4. RPC: Get unseen questions for a specific user
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_unseen_questions(
  p_user_id UUID,
  p_count INT DEFAULT 10,
  p_category TEXT DEFAULT NULL,
  p_difficulty TEXT DEFAULT NULL,
  p_exclude_superadmin BOOLEAN DEFAULT true
)
RETURNS SETOF public.quiz_questions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT q.*
  FROM public.quiz_questions q
  WHERE q.id NOT IN (
    SELECT ua.question_id
    FROM public.user_answered_questions ua
    WHERE ua.user_id = p_user_id
  )
  AND (p_exclude_superadmin = false OR q.is_superadmin_only = false)
  AND (p_category IS NULL OR q.category = p_category)
  AND (p_difficulty IS NULL OR q.difficulty = p_difficulty)
  ORDER BY RANDOM()
  LIMIT p_count;
END;
$$;

-- =====================================================
-- 5. RPC: Count unseen questions for a user
-- =====================================================

CREATE OR REPLACE FUNCTION public.count_unseen_questions(
  p_user_id UUID,
  p_category TEXT DEFAULT NULL,
  p_difficulty TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM public.quiz_questions q
  WHERE q.id NOT IN (
    SELECT ua.question_id
    FROM public.user_answered_questions ua
    WHERE ua.user_id = p_user_id
  )
  AND q.is_superadmin_only = false
  AND (p_category IS NULL OR q.category = p_category)
  AND (p_difficulty IS NULL OR q.difficulty = p_difficulty);

  RETURN v_count;
END;
$$;

-- =====================================================
-- 6. RPC: Record answered questions (batch insert)
-- =====================================================

CREATE OR REPLACE FUNCTION public.record_answered_questions(
  p_user_id UUID,
  p_question_ids UUID[],
  p_match_id UUID DEFAULT NULL,
  p_event_id UUID DEFAULT NULL,
  p_is_correct BOOLEAN[] DEFAULT NULL,
  p_response_times_ms INT[] DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted INT := 0;
  i INT;
BEGIN
  FOR i IN 1..array_length(p_question_ids, 1) LOOP
    INSERT INTO public.user_answered_questions (
      user_id, question_id, match_id, event_id, is_correct, response_time_ms
    ) VALUES (
      p_user_id,
      p_question_ids[i],
      p_match_id,
      p_event_id,
      COALESCE(p_is_correct[i], false),
      COALESCE(p_response_times_ms[i], 0)
    )
    ON CONFLICT DO NOTHING;

    IF FOUND THEN
      v_inserted := v_inserted + 1;
    END IF;
  END LOOP;

  RETURN v_inserted;
END;
$$;

-- =====================================================
-- 7. RPC: Submit tournament answers in batch
-- =====================================================

CREATE OR REPLACE FUNCTION public.submit_tournament_answers_batch(
  p_user_id UUID,
  p_event_id UUID,
  p_question_ids UUID[],
  p_answers INT[],
  p_response_times_ms INT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score INT := 0;
  v_correct INT := 0;
  v_total INT;
  i INT;
  v_question RECORD;
BEGIN
  v_total := array_length(p_question_ids, 1);

  FOR i IN 1..v_total LOOP
    -- Get the correct answer for this question
    SELECT * INTO v_question
    FROM public.quiz_questions
    WHERE id = p_question_ids[i];

    IF v_question IS NULL THEN
      CONTINUE;
    END IF;

    -- Check if answer is correct
    IF p_answers[i] = v_question.correct_answer THEN
      v_correct := v_correct + 1;
      v_score := v_score + v_question.points;
    END IF;

    -- Record the answer (ignore duplicates)
    INSERT INTO public.user_answered_questions (
      user_id, question_id, event_id, is_correct, response_time_ms
    ) VALUES (
      p_user_id,
      p_question_ids[i],
      p_event_id,
      p_answers[i] = v_question.correct_answer,
      COALESCE(p_response_times_ms[i], 0)
    ) ON CONFLICT DO NOTHING;
  END LOOP;

  -- Update the participant record
  UPDATE public.quiz_event_participants
  SET score = v_score,
      correct_count = v_correct,
      total_questions = v_total,
      completed_at = now()
  WHERE event_id = p_event_id AND user_id = p_user_id;

  RETURN jsonb_build_object(
    'score', v_score,
    'correct', v_correct,
    'total', v_total,
    'accuracy', CASE WHEN v_total > 0 THEN ROUND(v_correct::NUMERIC / v_total, 2) ELSE 0 END
  );
END;
$$;

-- =====================================================
-- 8. RPC: Get question bank stats (for admin/dashboard)
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_question_bank_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total INT;
  v_ai_generated INT;
  v_categories JSONB;
  v_difficulties JSONB;
BEGIN
  SELECT COUNT(*) INTO v_total FROM public.quiz_questions;
  SELECT COUNT(*) INTO v_ai_generated FROM public.quiz_questions WHERE ai_generated = true;

  SELECT jsonb_agg(jsonb_build_object('category', cat, 'count', cnt))
  INTO v_categories
  FROM (
    SELECT category AS cat, COUNT(*) AS cnt
    FROM public.quiz_questions
    GROUP BY category
    ORDER BY cnt DESC
  ) sub;

  SELECT jsonb_agg(jsonb_build_object('difficulty', diff, 'count', cnt))
  INTO v_difficulties
  FROM (
    SELECT difficulty AS diff, COUNT(*) AS cnt
    FROM public.quiz_questions
    GROUP BY difficulty
    ORDER BY cnt DESC
  ) sub;

  RETURN jsonb_build_object(
    'total', v_total,
    'ai_generated', v_ai_generated,
    'manual', v_total - v_ai_generated,
    'categories', COALESCE(v_categories, '[]'::jsonb),
    'difficulties', COALESCE(v_difficulties, '[]'::jsonb)
  );
END;
$$;
