-- ═══════════════════════════════════════════════════════════════
-- Performance: Missing indexes for launch readiness
-- Adds indexes on frequently-queried columns missing coverage
-- Each block checks table existence first
-- ═══════════════════════════════════════════════════════════════

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'messages' AND relnamespace = 'public'::regnamespace) THEN
  CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON public.messages(sender_id);
  CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
  CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON public.messages(conversation_id, created_at DESC);
END IF; END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'stream_chat_messages' AND relnamespace = 'public'::regnamespace) THEN
  CREATE INDEX IF NOT EXISTS idx_stream_chat_stream_id ON public.stream_chat_messages(stream_id);
  CREATE INDEX IF NOT EXISTS idx_stream_chat_user_id ON public.stream_chat_messages(user_id);
  CREATE INDEX IF NOT EXISTS idx_stream_chat_created ON public.stream_chat_messages(stream_id, created_at ASC);
END IF; END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'stream_prayer_requests' AND relnamespace = 'public'::regnamespace) THEN
  CREATE INDEX IF NOT EXISTS idx_stream_prayer_stream_id ON public.stream_prayer_requests(stream_id);
END IF; END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'fundraising_contributions' AND relnamespace = 'public'::regnamespace) THEN
  CREATE INDEX IF NOT EXISTS idx_fundraising_contributions_contributor ON public.fundraising_contributions(contributor_id);
  CREATE INDEX IF NOT EXISTS idx_fundraising_contributions_venture_created ON public.fundraising_contributions(venture_id, created_at DESC);
END IF; END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'live_streams' AND relnamespace = 'public'::regnamespace) THEN
  CREATE INDEX IF NOT EXISTS idx_live_streams_church_status ON public.live_streams(church_id, status);
  CREATE INDEX IF NOT EXISTS idx_live_streams_church_scheduled ON public.live_streams(church_id, scheduled_at DESC);
  CREATE INDEX IF NOT EXISTS idx_live_streams_created_by ON public.live_streams(created_by);
END IF; END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'community_communities' AND relnamespace = 'public'::regnamespace) THEN
  CREATE INDEX IF NOT EXISTS idx_community_communities_tenant ON public.community_communities(tenant_id);
END IF; END $$;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'community_members' AND relnamespace = 'public'::regnamespace) THEN
  CREATE INDEX IF NOT EXISTS idx_community_members_tenant ON public.community_members(tenant_id);
  CREATE INDEX IF NOT EXISTS idx_community_members_community_user ON public.community_members(community_id, user_id);
END IF; END $$;

-- Summary: count indexes created
SELECT COUNT(*) AS total_indexes
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('messages','stream_chat_messages','fundraising_contributions','live_streams','community_communities','community_members','stream_prayer_requests')
  AND indexname LIKE 'idx_%';
