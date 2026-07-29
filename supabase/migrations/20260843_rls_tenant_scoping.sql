-- ═══════════════════════════════════════════════════════════════
-- Cross-Tenant RLS Fix: Scope SELECT policies by tenant_id
-- Fixes data leak where any authenticated user can read ALL
-- churches' data via direct API.
-- NOTE: profiles.tenant_id is TEXT, scoped tables use UUID
-- ═══════════════════════════════════════════════════════════════

-- ── SOCIAL POSTS ─────────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "social_posts_select_auth" ON public.social_posts;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "Authenticated users can update social posts" ON public.social_posts;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'social_posts') THEN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'social_posts' AND policyname = 'social_posts_select_tenant') THEN
    CREATE POLICY "social_posts_select_tenant" ON public.social_posts
      FOR SELECT TO authenticated
      USING (tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'social_posts' AND policyname = 'social_posts_select_superadmin') THEN
    CREATE POLICY "social_posts_select_superadmin" ON public.social_posts
      FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee')));
  END IF;
END IF; END $$;

-- ── SERMONS ──────────────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view sermons" ON public.sermons;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'sermons') THEN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'sermons' AND policyname = 'Sermons select tenant scoped') THEN
    CREATE POLICY "Sermons select tenant scoped" ON public.sermons
      FOR SELECT TO authenticated
      USING (church_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));
  END IF;
END IF; END $$;

-- ── EVENTS ───────────────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view events" ON public.events;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'events') THEN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'events' AND policyname = 'Events select tenant scoped') THEN
    CREATE POLICY "Events select tenant scoped" ON public.events
      FOR SELECT TO authenticated
      USING (tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));
  END IF;
END IF; END $$;

-- ── LIVE CHAT MESSAGES ───────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can read live chat" ON public.live_chat_messages;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'live_chat_messages') THEN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'live_chat_messages' AND policyname = 'Live chat select tenant scoped') THEN
    CREATE POLICY "Live chat select tenant scoped" ON public.live_chat_messages
      FOR SELECT TO authenticated
      USING (tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));
  END IF;
END IF; END $$;

-- ── MARKETPLACE ITEMS ────────────────────────────────────────
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can view marketplace items" ON public.marketplace_items;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'marketplace_items') THEN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'marketplace_items' AND policyname = 'Marketplace items select tenant scoped') THEN
    CREATE POLICY "Marketplace items select tenant scoped" ON public.marketplace_items
      FOR SELECT TO authenticated
      USING (status = 'active' AND tenant_id::text IN (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));
  END IF;
END IF; END $$;

-- ── QUIZ RESULTS ─────────────────────────────────────────────
DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'quiz_results') THEN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'quiz_results' AND cmd = 'SELECT') THEN
    CREATE POLICY "Quiz results select own" ON public.quiz_results
      FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'quiz_results' AND cmd = 'INSERT') THEN
    CREATE POLICY "Quiz results insert own" ON public.quiz_results
      FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'quiz_results' AND cmd = 'UPDATE') THEN
    CREATE POLICY "Quiz results update own" ON public.quiz_results
      FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
  END IF;
END IF; END $$;

-- ═══════════════════════════════════════════════════════════════
-- COA Payments: add columns + constraints + indexes
-- ═══════════════════════════════════════════════════════════════

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coa_payments' AND column_name='webhook_idempotency') THEN
    ALTER TABLE public.coa_payments ADD COLUMN webhook_idempotency TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'coa_payments_webhook_idempotency_key') THEN
    ALTER TABLE public.coa_payments ADD CONSTRAINT coa_payments_webhook_idempotency_key UNIQUE (webhook_idempotency);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coa_payments' AND column_name='phone_number') THEN
    ALTER TABLE public.coa_payments ADD COLUMN phone_number TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coa_payments' AND column_name='network') THEN
    ALTER TABLE public.coa_payments ADD COLUMN network TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coa_payments' AND column_name='settled_at') THEN
    ALTER TABLE public.coa_payments ADD COLUMN settled_at TIMESTAMPTZ;
  END IF;
  CREATE INDEX IF NOT EXISTS idx_coa_payments_payment_ref ON public.coa_payments(payment_ref);
  CREATE INDEX IF NOT EXISTS idx_coa_payments_status ON public.coa_payments(status);
END $$;

-- Audit: confirm policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename IN ('social_posts','sermons','events','live_chat_messages','marketplace_items','quiz_results')
ORDER BY tablename, policyname;
