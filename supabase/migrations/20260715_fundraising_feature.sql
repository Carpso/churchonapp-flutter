-- Fundraising ventures table
CREATE TABLE IF NOT EXISTS fundraising_ventures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'Other',
  target_amount DOUBLE PRECISION NOT NULL,
  raised_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'ZMW',
  status TEXT NOT NULL DEFAULT 'active',
  start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date TIMESTAMPTZ,
  image_url TEXT,
  allow_other_tenants BOOLEAN NOT NULL DEFAULT false,
  allowed_tenant_ids UUID[] DEFAULT '{}',
  created_by UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fundraising contributions table
CREATE TABLE IF NOT EXISTS fundraising_contributions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venture_id UUID REFERENCES fundraising_ventures(id) ON DELETE CASCADE NOT NULL,
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE NOT NULL,
  tenant_name TEXT,
  contributor_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  contributor_name TEXT,
  amount DOUBLE PRECISION NOT NULL,
  is_anonymous BOOLEAN NOT NULL DEFAULT false,
  message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fundraising invites table
CREATE TABLE IF NOT EXISTS fundraising_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venture_id UUID REFERENCES fundraising_ventures(id) ON DELETE CASCADE NOT NULL,
  from_tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE NOT NULL,
  to_tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Function to increment raised_amount
CREATE OR REPLACE FUNCTION increment_fundraising_raised(venture_id UUID, amount DOUBLE PRECISION)
RETURNS VOID AS $$
BEGIN
  UPDATE fundraising_ventures
  SET raised_amount = raised_amount + amount
  WHERE id = venture_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_fundraising_ventures_tenant ON fundraising_ventures(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fundraising_ventures_status ON fundraising_ventures(status);
CREATE INDEX IF NOT EXISTS idx_fundraising_contributions_venture ON fundraising_contributions(venture_id);
CREATE INDEX IF NOT EXISTS idx_fundraising_invites_to_tenant ON fundraising_invites(to_tenant_id);

-- RLS
ALTER TABLE fundraising_ventures ENABLE ROW LEVEL SECURITY;
ALTER TABLE fundraising_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE fundraising_invites ENABLE ROW LEVEL SECURITY;

-- Everyone can view active ventures
DROP POLICY IF EXISTS "Anyone can view active ventures" ON fundraising_ventures;
CREATE POLICY "Anyone can view active ventures"
  ON fundraising_ventures FOR SELECT
  USING (status = 'active' OR tenant_id = auth.uid()::text::uuid);

-- Only tenant admins can create ventures
DROP POLICY IF EXISTS "Tenant admins can create ventures" ON fundraising_ventures;
CREATE POLICY "Tenant admins can create ventures"
  ON fundraising_ventures FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND (role IN ('superadmin', 'admin', 'pastor', 'bishop'))
      AND tenant_id::uuid = fundraising_ventures.tenant_id
    )
  );

-- Anyone authenticated can view contributions
DROP POLICY IF EXISTS "Anyone can view contributions" ON fundraising_contributions;
CREATE POLICY "Anyone can view contributions"
  ON fundraising_contributions FOR SELECT
  USING (true);

-- Authenticated users can contribute
DROP POLICY IF EXISTS "Authenticated users can contribute" ON fundraising_contributions;
CREATE POLICY "Authenticated users can contribute"
  ON fundraising_contributions FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- View invites sent to your tenant
DROP POLICY IF EXISTS "Tenants can view their invites" ON fundraising_invites;
CREATE POLICY "Tenants can view their invites"
  ON fundraising_invites FOR SELECT
  USING (to_tenant_id = auth.uid()::text::uuid OR from_tenant_id = auth.uid()::text::uuid);

-- Allow tenant admins to send invites
DROP POLICY IF EXISTS "Tenant admins can send invites" ON fundraising_invites;
CREATE POLICY "Tenant admins can send invites"
  ON fundraising_invites FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND (role IN ('superadmin', 'admin', 'pastor', 'bishop'))
      AND tenant_id::uuid = fundraising_invites.from_tenant_id
    )
  );

-- =============================================
-- Group Contributions (Collective Giving)
-- =============================================

CREATE TABLE IF NOT EXISTS group_contributions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  target_amount DOUBLE PRECISION NOT NULL,
  collected_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'ZMW',
  frequency TEXT NOT NULL DEFAULT 'one_time',
  status TEXT NOT NULL DEFAULT 'active',
  start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date TIMESTAMPTZ,
  min_amount DOUBLE PRECISION NOT NULL DEFAULT 1,
  max_amount DOUBLE PRECISION,
  created_by UUID REFERENCES auth.users(id) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS group_contribution_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES group_contributions(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  user_name TEXT NOT NULL,
  pledged_amount DOUBLE PRECISION NOT NULL,
  paid_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS group_contribution_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID REFERENCES group_contributions(id) ON DELETE CASCADE NOT NULL,
  member_id UUID REFERENCES group_contribution_members(id) ON DELETE CASCADE NOT NULL,
  user_name TEXT NOT NULL,
  amount DOUBLE PRECISION NOT NULL,
  is_anonymous BOOLEAN NOT NULL DEFAULT false,
  message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Increment collected_amount
CREATE OR REPLACE FUNCTION increment_group_collected(group_id UUID, amount DOUBLE PRECISION)
RETURNS VOID AS $$
BEGIN
  UPDATE group_contributions
  SET collected_amount = collected_amount + amount
  WHERE id = group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment member paid_amount
CREATE OR REPLACE FUNCTION increment_member_paid(member_id UUID, amount DOUBLE PRECISION)
RETURNS VOID AS $$
BEGIN
  UPDATE group_contribution_members
  SET paid_amount = paid_amount + amount
  WHERE id = member_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_group_contributions_tenant ON group_contributions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_group_contributions_status ON group_contributions(status);
CREATE INDEX IF NOT EXISTS idx_group_contribution_members_group ON group_contribution_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_contribution_payments_group ON group_contribution_payments(group_id);

-- RLS
ALTER TABLE group_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_contribution_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_contribution_payments ENABLE ROW LEVEL SECURITY;

-- Anyone in the tenant can view groups
DROP POLICY IF EXISTS "Tenant members can view group contributions" ON group_contributions;
CREATE POLICY "Tenant members can view group contributions"
  ON group_contributions FOR SELECT
  USING (
    tenant_id IN (
      SELECT tenant_id::uuid FROM profiles WHERE id = auth.uid()
    )
  );

-- Tenant admins can create groups
DROP POLICY IF EXISTS "Tenant admins can create group contributions" ON group_contributions;
CREATE POLICY "Tenant admins can create group contributions"
  ON group_contributions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND (role IN ('superadmin', 'admin', 'pastor', 'bishop'))
      AND tenant_id::uuid = group_contributions.tenant_id
    )
  );

-- Members can view other members in their group
DROP POLICY IF EXISTS "Members can view group members" ON group_contribution_members;
CREATE POLICY "Members can view group members"
  ON group_contribution_members FOR SELECT
  USING (true);

-- Authenticated users can join groups
DROP POLICY IF EXISTS "Authenticated users can join groups" ON group_contribution_members;
CREATE POLICY "Authenticated users can join groups"
  ON group_contribution_members FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Anyone can view payments
DROP POLICY IF EXISTS "Anyone can view group payments" ON group_contribution_payments;
CREATE POLICY "Anyone can view group payments"
  ON group_contribution_payments FOR SELECT
  USING (true);

-- Authenticated users can contribute
DROP POLICY IF EXISTS "Authenticated users can contribute to groups" ON group_contribution_payments;
CREATE POLICY "Authenticated users can contribute to groups"
  ON group_contribution_payments FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');
