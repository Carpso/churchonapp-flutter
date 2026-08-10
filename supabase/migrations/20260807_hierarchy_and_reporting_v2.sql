-- ═══════════════════════════════════════════════════════════════════════════════
-- CHURCH ON APP: MULTI-TENANT HIERARCHY, REPORTING & GLOBAL QUIZ SCHEMA (V2)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. TOP-LEVEL ORGANIZATIONS (Updated with 'code' column)
ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS code TEXT UNIQUE;
ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS logo_url TEXT;

-- 2. DYNAMIC HIERARCHY LEVELS PER ORGANIZATION
CREATE TABLE IF NOT EXISTS public.hierarchy_levels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL, -- e.g., 'National HQ', 'Presbytery/Region', 'District', 'Local Assembly'
    rank_order INTEGER NOT NULL, -- 1 = Top Level (HQ), 2 = Region, 3 = District, 4 = Local Branch
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(organization_id, rank_order)
);

-- 3. HIERARCHY NODES (TREE STRUCTURE FOR BRANCHES AND REGIONS)
CREATE TABLE IF NOT EXISTS public.hierarchy_nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    level_id UUID NOT NULL REFERENCES public.hierarchy_levels(id),
    parent_node_id UUID REFERENCES public.hierarchy_nodes(id) ON DELETE CASCADE, -- Self-referencing tree
    name TEXT NOT NULL, -- e.g., 'Lusaka Presbytery', 'Faith Assembly - Matero'
    tenant_id UUID REFERENCES public.churches(id), -- Populated only for local assemblies
    leader_user_id UUID REFERENCES auth.users(id), -- Overseer, Pastor, or Regional Superintendent
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. NATIONAL & REGIONAL EXECUTIVE ROLES (CROSS-BRANCH SCOPE WITHIN ORGANIZATION)
CREATE TABLE IF NOT EXISTS public.user_organization_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    node_id UUID REFERENCES public.hierarchy_nodes(id) ON DELETE CASCADE, -- Null means full National HQ scope
    role_key TEXT NOT NULL, -- 'bishop', 'general_superintendent', 'assistant_superintendent', 'general_secretary', 'general_treasurer', 'regional_overseer'
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, organization_id, role_key, node_id)
);

-- 5. HIERARCHICAL REPORTING PIPELINE
CREATE TABLE IF NOT EXISTS public.hierarchical_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    node_id UUID NOT NULL REFERENCES public.hierarchy_nodes(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES auth.users(id),
    report_type TEXT CHECK (report_type IN ('financial', 'membership', 'ministry', 'executive')),
    title TEXT NOT NULL,
    content JSONB NOT NULL,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'pending_local_approval', 'pending_regional_review', 'approved_hq', 'rejected')),
    current_level_rank INTEGER NOT NULL DEFAULT 4, -- Matches hierarchy_levels.rank_order
    approval_chain JSONB DEFAULT '[]'::jsonb, -- Immutable log of sign-offs
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 6. GLOBAL PLATFORM-OWNED BIBLE QUIZZING (CHURCH ON APP CENTRAL ASSET)
CREATE TABLE IF NOT EXISTS public.platform_quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    category TEXT NOT NULL, -- 'Gospels', 'Apostolic History', 'Doctrine'
    difficulty_rating INTEGER DEFAULT 1200,
    questions JSONB NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.platform_quiz_leaderboard (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    elo_rating INTEGER DEFAULT 1200,
    matches_played INTEGER DEFAULT 0,
    matches_won INTEGER DEFAULT 0,
    current_streak INTEGER DEFAULT 0,
    total_coins_earned BIGINT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hierarchy_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hierarchy_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_organization_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hierarchical_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_quizzes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_quiz_leaderboard ENABLE ROW LEVEL SECURITY;

-- ORGANIZATIONS & HIERARCHY READ POLICY
DROP POLICY IF EXISTS "Users can read their organization structure" ON public.hierarchy_nodes;
CREATE POLICY "Users can read their organization structure" ON public.hierarchy_nodes
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_organization_roles uor
            WHERE uor.user_id = auth.uid()
            AND uor.organization_id = hierarchy_nodes.organization_id
        )
        OR leader_user_id = auth.uid()
    );

-- BISHOP & NATIONAL EXECUTIVE REPORTING POLICY (READ ALL REPORTS WITHIN THEIR ORGANIZATION)
DROP POLICY IF EXISTS "Executive Organization Report Scope" ON public.hierarchical_reports;
CREATE POLICY "Executive Organization Report Scope" ON public.hierarchical_reports
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_organization_roles uor
            WHERE uor.user_id = auth.uid()
            AND uor.organization_id = hierarchical_reports.organization_id
            AND uor.role_key IN ('bishop', 'general_superintendent', 'assistant_superintendent', 'general_secretary', 'general_treasurer')
        )
        OR author_id = auth.uid()
    );

-- LOCAL & REGIONAL REPORT SUBMISSION / UPDATE POLICY
DROP POLICY IF EXISTS "Author or Leader Report Update Policy" ON public.hierarchical_reports;
CREATE POLICY "Author or Leader Report Update Policy" ON public.hierarchical_reports
    FOR UPDATE TO authenticated
    USING (
        author_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.hierarchy_nodes hn
            WHERE hn.id = hierarchical_reports.node_id
            AND hn.leader_user_id = auth.uid()
        )
    );

-- GLOBAL QUIZ POLICIES (ALL AUTHENTICATED USERS CAN READ AND COMPETE)
DROP POLICY IF EXISTS "Public Read Platform Quizzes" ON public.platform_quizzes;
CREATE POLICY "Public Read Platform Quizzes" ON public.platform_quizzes
    FOR SELECT TO authenticated USING (is_active = true);

DROP POLICY IF EXISTS "Public Read Platform Leaderboard" ON public.platform_quiz_leaderboard;
CREATE POLICY "Public Read Platform Leaderboard" ON public.platform_quiz_leaderboard
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "User Update Own Leaderboard Score" ON public.platform_quiz_leaderboard;
CREATE POLICY "User Update Own Leaderboard Score" ON public.platform_quiz_leaderboard
    FOR ALL TO authenticated USING (user_id = auth.uid());

-- ═══════════════════════════════════════════════════════════════════════════════
-- SEED DATA: UPCZ ZAMBIAN REGIONAL PRESBYTERIES
-- ═══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_org_id UUID;
    v_level_hq UUID;
    v_level_region UUID;
    v_level_district UUID;
    v_level_local UUID;
    v_node_hq UUID;
    v_node_lusaka UUID;
    v_node_copperbelt UUID;
    v_node_southern UUID;
    v_node_central UUID;
    v_node_eastern UUID;
BEGIN
    -- 1. Create Organization
    INSERT INTO public.organizations (name, code)
    VALUES ('United Pentecostal Church in Zambia', 'UPCZ')
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_org_id;

    -- 2. Create Hierarchy Levels
    INSERT INTO public.hierarchy_levels (organization_id, name, rank_order) VALUES
    (v_org_id, 'National HQ', 1),
    (v_org_id, 'Presbytery/Region', 2),
    (v_org_id, 'District', 3),
    (v_org_id, 'Local Assembly', 4)
    ON CONFLICT (organization_id, rank_order) DO UPDATE SET name = EXCLUDED.name;

    SELECT id INTO v_level_hq FROM public.hierarchy_levels WHERE organization_id = v_org_id AND rank_order = 1;
    SELECT id INTO v_level_region FROM public.hierarchy_levels WHERE organization_id = v_org_id AND rank_order = 2;
    SELECT id INTO v_level_district FROM public.hierarchy_levels WHERE organization_id = v_org_id AND rank_order = 3;
    SELECT id INTO v_level_local FROM public.hierarchy_levels WHERE organization_id = v_org_id AND rank_order = 4;

    -- 3. Create Hierarchy Nodes (Regions)
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, name)
    VALUES (v_org_id, v_level_hq, 'UPCZ National Headquarters')
    RETURNING id INTO v_node_hq;

    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name) VALUES
    (v_org_id, v_level_region, v_node_hq, 'Lusaka Presbytery'),
    (v_org_id, v_level_region, v_node_hq, 'Copperbelt Presbytery'),
    (v_org_id, v_level_region, v_node_hq, 'Southern Presbytery'),
    (v_org_id, v_level_region, v_node_hq, 'Central Presbytery'),
    (v_org_id, v_level_region, v_node_hq, 'Eastern Presbytery');

    SELECT id INTO v_node_lusaka FROM public.hierarchy_nodes WHERE organization_id = v_org_id AND name = 'Lusaka Presbytery';
    SELECT id INTO v_node_copperbelt FROM public.hierarchy_nodes WHERE organization_id = v_org_id AND name = 'Copperbelt Presbytery';
    SELECT id INTO v_node_southern FROM public.hierarchy_nodes WHERE organization_id = v_org_id AND name = 'Southern Presbytery';
    SELECT id INTO v_node_central FROM public.hierarchy_nodes WHERE organization_id = v_org_id AND name = 'Central Presbytery';
    SELECT id INTO v_node_eastern FROM public.hierarchy_nodes WHERE organization_id = v_org_id AND name = 'Eastern Presbytery';

    -- 4. Create Local Assemblies (Linking to existing churches if found)
    -- Lusaka
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name, tenant_id)
    VALUES (v_org_id, v_level_local, v_node_lusaka, 'Matero Assembly', 'c882e91e-ca67-4163-9f07-5aa83ab1d470');
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name)
    VALUES (v_org_id, v_level_local, v_node_lusaka, 'Chilenje Assembly'),
           (v_org_id, v_level_local, v_node_lusaka, 'Garden Compound Assembly');

    -- Copperbelt
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name)
    VALUES (v_org_id, v_level_local, v_node_copperbelt, 'Ndola Central Assembly'),
           (v_org_id, v_level_local, v_node_copperbelt, 'Kitwe Nkana Assembly'),
           (v_org_id, v_level_local, v_node_copperbelt, 'Mufulira Assembly');

    -- Southern
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name, tenant_id)
    VALUES (v_org_id, v_level_local, v_node_southern, 'Livingstone Assembly', '62b34806-8d0d-4b27-ad6a-48d15cda5c37'),
           (v_org_id, v_level_local, v_node_southern, 'Choma Assembly', '7248529e-141f-4eb0-9739-9dca39f5afbe');

    -- Central
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name, tenant_id)
    VALUES (v_org_id, v_level_local, v_node_central, 'Kabwe Assembly', '930c6af3-0acd-487b-aaee-b88d37454a7f');

    -- Eastern
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name, tenant_id)
    VALUES (v_org_id, v_level_local, v_node_eastern, 'Chipata Assembly', '7934466e-6e38-4af6-a490-d24e12836e92');

END $$;
