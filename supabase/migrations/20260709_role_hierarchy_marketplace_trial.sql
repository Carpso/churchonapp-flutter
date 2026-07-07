-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. ROLE HIERARCHY SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════════

-- Tenant-specific custom roles (created by main role leads)
CREATE TABLE IF NOT EXISTS public.tenant_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    role_name TEXT NOT NULL,
    display_name TEXT,
    description TEXT,
    parent_role_id UUID REFERENCES public.tenant_roles(id) ON DELETE SET NULL,
    created_by UUID REFERENCES auth.users(id),
    is_system_role BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(tenant_id, role_name)
);

ALTER TABLE public.tenant_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view tenant roles" ON public.tenant_roles
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Superadmins and employees can manage all roles" ON public.tenant_roles
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

CREATE POLICY "Main role leads can create roles in own tenant" ON public.tenant_roles
    FOR INSERT TO authenticated WITH CHECK (
        tenant_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND role IN ('bishop', 'pastor', 'bookshop_owner', 'prophet', 'apostle', 'admin', 'superadmin', 'employee')
        )
    );

-- Role assignments (tracks approvals)
CREATE TABLE IF NOT EXISTS public.role_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role_name TEXT NOT NULL,
    assigned_by UUID REFERENCES auth.users(id),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    approved_at TIMESTAMPTZ,
    rejected_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.role_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own assignments" ON public.role_assignments
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "Superadmins/employees can manage all assignments" ON public.role_assignments
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

CREATE POLICY "Main role leads can view assignments in own tenant" ON public.role_assignments
    FOR SELECT TO authenticated USING (
        tenant_id IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND role IN ('bishop', 'pastor', 'bookshop_owner', 'prophet', 'apostle', 'admin', 'superadmin', 'employee')
        )
    );

CREATE INDEX IF NOT EXISTS idx_role_assignments_user ON public.role_assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_role_assignments_tenant ON public.role_assignments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_role_assignments_status ON public.role_assignments(status);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. MARKETPLACE ORDERS + DELIVERY
-- ═══════════════════════════════════════════════════════════════════════════════

-- Orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.churches(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
    total_amount DOUBLE PRECISION NOT NULL DEFAULT 0,
    delivery_fee DOUBLE PRECISION DEFAULT 0,
    platform_fee DOUBLE PRECISION DEFAULT 0,
    payment_reference TEXT,
    payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
    shipping_address TEXT,
    contact_phone TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own orders" ON public.orders
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "Users can create own orders" ON public.orders
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Moved after order_items table creation below

CREATE POLICY "Superadmins and employees can view all orders" ON public.orders
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_orders_user ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);

-- Order items
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    item_id UUID REFERENCES public.marketplace_items(id) ON DELETE SET NULL,
    item_name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price DOUBLE PRECISION NOT NULL,
    total_price DOUBLE PRECISION NOT NULL,
    vendor_id UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own order items" ON public.order_items
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.orders WHERE id = order_items.order_id AND user_id = auth.uid())
    );

CREATE POLICY "Vendors can view items from their products" ON public.order_items
    FOR SELECT TO authenticated USING (vendor_id = auth.uid());

CREATE POLICY "Superadmins can view all items" ON public.order_items
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);

-- Vendors policy for orders table (must be after order_items creation)
CREATE POLICY "Vendors can view orders for their items" ON public.orders
    FOR SELECT TO authenticated USING (
        EXISTS (
            SELECT 1 FROM public.order_items oi
            JOIN public.marketplace_items mi ON oi.item_id = mi.id
            WHERE oi.order_id = orders.id AND mi.vendor_id = auth.uid()
        )
    );

-- Delivery tracking
CREATE TABLE IF NOT EXISTS public.deliveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
    delivery_request_id UUID REFERENCES public.delivery_requests(id) ON DELETE SET NULL,
    driver_id UUID REFERENCES auth.users(id),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'assigned', 'picked_up', 'in_transit', 'delivered', 'failed')),
    pickup_address TEXT,
    delivery_address TEXT,
    pickup_lat DOUBLE PRECISION,
    pickup_lng DOUBLE PRECISION,
    delivery_lat DOUBLE PRECISION,
    delivery_lng DOUBLE PRECISION,
    estimated_delivery_time TIMESTAMPTZ,
    actual_delivery_time TIMESTAMPTZ,
    proof_of_delivery_url TEXT,
    recipient_name TEXT,
    recipient_phone TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own deliveries" ON public.deliveries
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.orders WHERE id = deliveries.order_id AND user_id = auth.uid())
    );

CREATE POLICY "Drivers can view assigned deliveries" ON public.deliveries
    FOR SELECT TO authenticated USING (driver_id = auth.uid());

CREATE POLICY "Superadmins can manage deliveries" ON public.deliveries
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_deliveries_order ON public.deliveries(order_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_driver ON public.deliveries(driver_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_status ON public.deliveries(status);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. WRITER APPLICATIONS & APPROVAL
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.writer_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    reason TEXT,
    writing_samples_url TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

ALTER TABLE public.writer_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own application" ON public.writer_applications
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own application" ON public.writer_applications
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Superadmins and employees can manage applications" ON public.writer_applications
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. 30-DAY TRIAL FOR CHURCHES
-- ═══════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS trial_started_at TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS trial_ends_at TIMESTAMPTZ;
ALTER TABLE public.churches ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trial'
    CHECK (subscription_status IN ('trial', 'active', 'expired', 'cancelled', 'suspended'));

-- Auto-set trial dates on insert
CREATE OR REPLACE FUNCTION public.set_church_trial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.trial_started_at IS NULL THEN
        NEW.trial_started_at := now();
        NEW.trial_ends_at := now() + INTERVAL '30 days';
        NEW.subscription_status := 'trial';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_churches_set_trial ON public.churches;
CREATE TRIGGER trg_churches_set_trial
    BEFORE INSERT ON public.churches
    FOR EACH ROW
    EXECUTE FUNCTION public.set_church_trial();

-- Check if church trial is active
CREATE OR REPLACE FUNCTION public.is_church_trial_active(church_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    status TEXT;
    ends_at TIMESTAMPTZ;
BEGIN
    SELECT subscription_status, trial_ends_at INTO status, ends_at
    FROM public.churches WHERE id = church_id;

    IF status = 'active' THEN
        RETURN true; -- paid subscription is active
    END IF;

    IF status = 'trial' AND ends_at IS NOT NULL AND ends_at > now() THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. CHURCH LEADS (pastor referrals from users who didn't find their church)
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.church_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referred_by_user_id UUID REFERENCES auth.users(id),
    referrer_name TEXT,
    referrer_phone TEXT,
    pastor_name TEXT NOT NULL,
    pastor_phone TEXT NOT NULL,
    church_name TEXT,
    church_location TEXT,
    notes TEXT,
    status TEXT DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'registered', 'converted', 'closed')),
    contacted_at TIMESTAMPTZ,
    registered_church_id UUID REFERENCES public.churches(id) ON DELETE SET NULL,
    assigned_to UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.church_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own referrals" ON public.church_leads
    FOR SELECT TO authenticated USING (referred_by_user_id = auth.uid());

CREATE POLICY "Users can create referrals" ON public.church_leads
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = referred_by_user_id);

CREATE POLICY "Superadmins and employees can manage all leads" ON public.church_leads
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_church_leads_status ON public.church_leads(status);
CREATE INDEX IF NOT EXISTS idx_church_leads_referrer ON public.church_leads(referred_by_user_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. REFERRALS TABLE (user referral system - previously missing from SQL)
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    referee_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    referee_email TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'expired')),
    reward_claimed BOOLEAN DEFAULT false,
    reward_amount DOUBLE PRECISION DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ
);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own referrals" ON public.referrals
    FOR SELECT TO authenticated USING (referrer_id = auth.uid());

CREATE POLICY "Users can create referrals" ON public.referrals
    FOR INSERT TO authenticated WITH CHECK (referrer_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON public.referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status ON public.referrals(status);

-- User purchases (what marketplace items a user has bought)
CREATE TABLE IF NOT EXISTS public.user_purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    item_id UUID REFERENCES public.marketplace_items(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    price DOUBLE PRECISION NOT NULL,
    quantity INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, item_id, order_id)
);

ALTER TABLE public.user_purchases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own purchases" ON public.user_purchases
    FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "Superadmins can view all purchases" ON public.user_purchases
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

CREATE INDEX IF NOT EXISTS idx_user_purchases_user ON public.user_purchases(user_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. NOTIFICATION TRIGGERS FOR ROLE ELEVATION & WRITER APPROVAL
-- ═══════════════════════════════════════════════════════════════════════════════

-- Notify user when role is approved via role_assignments
CREATE OR REPLACE FUNCTION public.notify_role_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status != 'approved') THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.user_id,
            'Role Approved',
            'Your role as ' || NEW.role_name || ' has been approved.',
            'role_change',
            NEW.id::text
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_role_approved ON public.role_assignments;
CREATE TRIGGER trg_notify_role_approved
    AFTER UPDATE OF status ON public.role_assignments
    FOR EACH ROW
    WHEN (NEW.status = 'approved')
    EXECUTE FUNCTION public.notify_role_approved();

-- Notify user when writer application is approved
CREATE OR REPLACE FUNCTION public.notify_writer_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status != 'approved') THEN
        -- Update profile role to writer
        UPDATE public.profiles SET role = 'writer' WHERE id = NEW.user_id;

        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.user_id,
            'Writer Status Approved',
            'Congratulations! Your writer application has been approved. You can now publish articles.',
            'writer_approved',
            NEW.id::text
        );
    ELSIF NEW.status = 'rejected' AND (OLD IS NULL OR OLD.status != 'rejected') THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.user_id,
            'Writer Application Update',
            'Your writer application was not approved. Reason: ' || COALESCE(NEW.rejection_reason, 'Not specified'),
            'writer_rejected',
            NEW.id::text
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_writer_approved ON public.writer_applications;
CREATE TRIGGER trg_notify_writer_approved
    AFTER UPDATE OF status ON public.writer_applications
    FOR EACH ROW
    WHEN (NEW.status IN ('approved', 'rejected'))
    EXECUTE FUNCTION public.notify_writer_approved();

-- Notify user when profile role is changed directly
CREATE OR REPLACE FUNCTION public.notify_profile_role_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF OLD.role != NEW.role THEN
        INSERT INTO public.notifications (user_id, title, body, type, reference_id)
        VALUES (
            NEW.id,
            'Role Updated',
            'Your platform role has been updated to: ' || NEW.role,
            'role_change',
            NEW.id::text
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_profile_role_change ON public.profiles;
CREATE TRIGGER trg_notify_profile_role_change
    AFTER UPDATE OF role ON public.profiles
    FOR EACH ROW
    WHEN (OLD.role IS DISTINCT FROM NEW.role)
    EXECUTE FUNCTION public.notify_profile_role_change();

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. ENABLE REALTIME
-- ═══════════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_publication p ON p.oid = pr.prpubid JOIN pg_class c ON c.oid = pr.prrelid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'orders') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE orders;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_publication p ON p.oid = pr.prpubid JOIN pg_class c ON c.oid = pr.prrelid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'deliveries') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE deliveries;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_publication p ON p.oid = pr.prpubid JOIN pg_class c ON c.oid = pr.prrelid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'role_assignments') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE role_assignments;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_rel pr JOIN pg_publication p ON p.oid = pr.prpubid JOIN pg_class c ON c.oid = pr.prrelid WHERE p.pubname = 'supabase_realtime' AND c.relname = 'writer_applications') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE writer_applications;
    END IF;
END $$;
