-- ═══════════════════════════════════════════════════════════════════════════════
-- CHURCH ON APP: FULL DEMO SEED SCRIPT (UPCZ NETWORK & EXECUTIVE DASHBOARDS)
-- ═══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    -- Organization & Hierarchy Level IDs
    v_org_id UUID := '11111111-1111-1111-1111-111111111111';
    v_lvl_hq UUID;
    v_lvl_reg UUID;
    v_lvl_loc UUID;

    -- Local Church Tenant IDs
    v_church_matero UUID := 'c882e91e-ca67-4163-9f07-5aa83ab1d470';
    v_church_ndola UUID := 'ad13c007-88ed-403d-ad43-d9c8a8f923f1';
    v_church_lstone UUID := '62b34806-8d0d-4b27-ad6a-48d15cda5c37';

    -- Hierarchy Node IDs
    v_node_nat_hq UUID;
    v_node_lusaka_reg UUID;

BEGIN

    -- 1. TOP-LEVEL ORGANIZATION: UPCZ
    INSERT INTO public.organizations (id, name, code, logo_url)
    VALUES (v_org_id, 'United Pentecostal Church in Zambia', 'UPCZ', 'https://media.churchonapp.com/logos/upcz_emblem.png')
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name
    RETURNING id INTO v_org_id;

    -- 2. HIERARCHY LEVELS
    INSERT INTO public.hierarchy_levels (organization_id, name, rank_order) VALUES
        (v_org_id, 'National Headquarters', 1),
        (v_org_id, 'Regional Presbytery', 2),
        (v_org_id, 'District Council', 3),
        (v_org_id, 'Local Assembly', 4)
    ON CONFLICT (organization_id, rank_order) DO UPDATE SET name = EXCLUDED.name;

    SELECT id INTO v_lvl_hq FROM public.hierarchy_levels WHERE organization_id = v_org_id AND rank_order = 1;
    SELECT id INTO v_lvl_reg FROM public.hierarchy_levels WHERE organization_id = v_org_id AND rank_order = 2;
    SELECT id INTO v_lvl_loc FROM public.hierarchy_levels WHERE organization_id = v_org_id AND rank_order = 4;

    -- 3. HIERARCHY TREE NODES
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name)
    VALUES (v_org_id, v_lvl_hq, NULL, 'UPCZ General Synod HQ - Lusaka')
    ON CONFLICT DO NOTHING;

    SELECT id INTO v_node_nat_hq FROM public.hierarchy_nodes WHERE organization_id = v_org_id AND level_id = v_lvl_hq;

    -- Level 2: Regional Presbyteries
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name) VALUES
        (v_org_id, v_lvl_reg, v_node_nat_hq, 'Lusaka Regional Presbytery'),
        (v_org_id, v_lvl_reg, v_node_nat_hq, 'Copperbelt Regional Presbytery'),
        (v_org_id, v_lvl_reg, v_node_nat_hq, 'Southern Regional Presbytery')
    ON CONFLICT DO NOTHING;

    SELECT id INTO v_node_lusaka_reg FROM public.hierarchy_nodes WHERE name='Lusaka Regional Presbytery' LIMIT 1;

    -- Level 4: Local Assembly Branches
    INSERT INTO public.hierarchy_nodes (organization_id, level_id, parent_node_id, name, tenant_id) VALUES
        (v_org_id, v_lvl_loc, v_node_lusaka_reg, 'Faith Assembly - Matero', v_church_matero),
        (v_org_id, v_lvl_loc, (SELECT id FROM public.hierarchy_nodes WHERE name='Copperbelt Regional Presbytery' LIMIT 1), 'Calvary Tabernacle - Ndola', v_church_ndola),
        (v_org_id, v_lvl_loc, (SELECT id FROM public.hierarchy_nodes WHERE name='Southern Regional Presbytery' LIMIT 1), 'Zambezi Revival - Livingstone', v_church_lstone)
    ON CONFLICT DO NOTHING;

END $$;
