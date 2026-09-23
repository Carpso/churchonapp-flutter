-- ============================================================================
-- Event Ticketing v2 (Ticketmaster-grade)
-- ----------------------------------------------------------------------------
-- Ticket tiers with per-tier capacity + sales windows, real orders, per-ticket
-- codes/QR, server-enforced atomic inventory (never client maths), idempotent
-- check-in, refunds, transfers, waitlist and event cancellation.
--
-- Payment rules (repo-wide, see PAYMENTS.md):
--   * The client never decides payer/payee/amount — totals are derived here
--     from event_ticket_tiers.price_kwacha.
--   * A paid order is anchored on a pre-created coa_payments row matching the
--     buyer + payment_ref. Never create a coa_payments row here.
--   * Pending orders are auto-confirmed when the coa_payments row settles.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_ticket_tiers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id        UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  tenant_id       UUID,
  name            TEXT NOT NULL,
  description     TEXT,
  price_kwacha    NUMERIC(12,2) NOT NULL DEFAULT 0,
  quantity_total  INTEGER,                       -- NULL = unlimited
  quantity_sold   INTEGER NOT NULL DEFAULT 0,
  max_per_order   INTEGER NOT NULL DEFAULT 10,
  sales_start     TIMESTAMPTZ,
  sales_end       TIMESTAMPTZ,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_event_ticket_tiers_event ON public.event_ticket_tiers(event_id);
CREATE INDEX IF NOT EXISTS idx_event_ticket_tiers_active ON public.event_ticket_tiers(event_id, is_active);

CREATE TABLE IF NOT EXISTS public.event_ticket_orders (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_ref     TEXT NOT NULL UNIQUE,
  event_id      UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  tenant_id     UUID,
  buyer_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tier_id       UUID REFERENCES public.event_ticket_tiers(id) ON DELETE SET NULL,
  quantity      INTEGER NOT NULL DEFAULT 1,
  unit_price    NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_amount  NUMERIC(12,2) NOT NULL DEFAULT 0,
  currency      TEXT NOT NULL DEFAULT 'ZMW',
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','paid','cancelled','refunded','failed')),
  payment_ref   TEXT,
  paid_at       TIMESTAMPTZ,
  refunded_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_event_ticket_orders_payment_ref
  ON public.event_ticket_orders(payment_ref) WHERE payment_ref IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_event_ticket_orders_event ON public.event_ticket_orders(event_id);
CREATE INDEX IF NOT EXISTS idx_event_ticket_orders_buyer ON public.event_ticket_orders(buyer_id);

CREATE TABLE IF NOT EXISTS public.event_tickets (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL REFERENCES public.event_ticket_orders(id) ON DELETE CASCADE,
  event_id         UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  tier_id          UUID REFERENCES public.event_ticket_tiers(id) ON DELETE SET NULL,
  tenant_id        UUID,
  owner_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ticket_code      TEXT NOT NULL UNIQUE,
  status           TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','valid','used','refunded','transferred','cancelled')),
  checked_in_at    TIMESTAMPTZ,
  checked_in_by    UUID REFERENCES public.profiles(id),
  transferred_to   UUID REFERENCES public.profiles(id),
  transferred_at   TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_event_tickets_event ON public.event_tickets(event_id);
CREATE INDEX IF NOT EXISTS idx_event_tickets_owner ON public.event_tickets(owner_id);
CREATE INDEX IF NOT EXISTS idx_event_tickets_code ON public.event_tickets(ticket_code);
CREATE INDEX IF NOT EXISTS idx_event_tickets_order ON public.event_tickets(order_id);

CREATE TABLE IF NOT EXISTS public.event_ticket_refunds (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id     UUID NOT NULL REFERENCES public.event_tickets(id) ON DELETE CASCADE,
  order_id      UUID NOT NULL REFERENCES public.event_ticket_orders(id) ON DELETE CASCADE,
  event_id      UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  reason        TEXT,
  status        TEXT NOT NULL DEFAULT 'completed'
                CHECK (status IN ('completed','failed')),
  processed_by  UUID REFERENCES public.profiles(id),
  refund_ref    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_event_ticket_refunds_event ON public.event_ticket_refunds(event_id);
CREATE INDEX IF NOT EXISTS idx_event_ticket_refunds_order ON public.event_ticket_refunds(order_id);

CREATE TABLE IF NOT EXISTS public.event_ticket_waitlist (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  tier_id     UUID REFERENCES public.event_ticket_tiers(id) ON DELETE SET NULL,
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  notified    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_event_ticket_waitlist_event ON public.event_ticket_waitlist(event_id);

CREATE TABLE IF NOT EXISTS public.event_ticket_audit (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id      UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  ticket_id     UUID REFERENCES public.event_tickets(id) ON DELETE SET NULL,
  action        TEXT NOT NULL,      -- check_in | transfer | refund | cancel
  status        TEXT NOT NULL,      -- valid | duplicate | invalid | success | error
  detail        TEXT,
  actor_id      UUID REFERENCES public.profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_event_ticket_audit_event ON public.event_ticket_audit(event_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_event_host(p_event_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.events e
    WHERE e.id = p_event_id
      AND (e.user_id = auth.uid() OR e.hosted_by = auth.uid() OR e.created_by = auth.uid())
  ) OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role IN (
        'superadmin','coa_employee','admin','bishop','apostle','prophet',
        'general_secretary','general_treasurer','treasurer','pastor','leader',
        'department_leader'
      )
  );
$$;
REVOKE EXECUTE ON FUNCTION public.is_event_host(UUID) FROM anon;

CREATE OR REPLACE FUNCTION public.new_ticket_code()
RETURNS TEXT LANGUAGE sql VOLATILE AS $$
  SELECT 'COA-TKT-' || to_char(now(), 'YYYY') || '-' ||
         upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
$$;

CREATE OR REPLACE FUNCTION public.new_order_ref()
RETURNS TEXT LANGUAGE sql VOLATILE AS $$
  SELECT 'COA-ORD-' || to_char(now(), 'YYYY') || '-' ||
         upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
$$;

CREATE OR REPLACE FUNCTION public.event_ticket_tiers_touch()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_event_ticket_tiers_touch ON public.event_ticket_tiers;
CREATE TRIGGER trg_event_ticket_tiers_touch
  BEFORE UPDATE ON public.event_ticket_tiers
  FOR EACH ROW EXECUTE FUNCTION public.event_ticket_tiers_touch();

-- ---------------------------------------------------------------------------
-- 3. RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.event_ticket_tiers    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_ticket_orders   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_tickets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_ticket_refunds  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_ticket_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_ticket_audit    ENABLE ROW LEVEL SECURITY;

-- Tiers: readable by everyone signed in (prices/capacity are public info).
DROP POLICY IF EXISTS "tiers_select" ON public.event_ticket_tiers;
CREATE POLICY "tiers_select" ON public.event_ticket_tiers
  FOR SELECT TO authenticated USING (TRUE);

DROP POLICY IF EXISTS "tiers_host_manage" ON public.event_ticket_tiers;
CREATE POLICY "tiers_host_manage" ON public.event_ticket_tiers
  FOR ALL TO authenticated
  USING (public.is_event_host(event_id))
  WITH CHECK (public.is_event_host(event_id));

-- Orders: buyer or host.
DROP POLICY IF EXISTS "orders_select" ON public.event_ticket_orders;
CREATE POLICY "orders_select" ON public.event_ticket_orders
  FOR SELECT TO authenticated
  USING (buyer_id = auth.uid() OR public.is_event_host(event_id));

-- Tickets: owner or host.
DROP POLICY IF EXISTS "tickets_select" ON public.event_tickets;
CREATE POLICY "tickets_select" ON public.event_tickets
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR public.is_event_host(event_id));

-- Refunds: buyer or host.
DROP POLICY IF EXISTS "ticket_refunds_select" ON public.event_ticket_refunds;
CREATE POLICY "ticket_refunds_select" ON public.event_ticket_refunds
  FOR SELECT TO authenticated
  USING (
    public.is_event_host(event_id)
    OR EXISTS (SELECT 1 FROM public.event_ticket_orders o
               WHERE o.id = order_id AND o.buyer_id = auth.uid())
  );

-- Waitlist: own rows only (hosts may see their event's waitlist).
DROP POLICY IF EXISTS "waitlist_select" ON public.event_ticket_waitlist;
CREATE POLICY "waitlist_select" ON public.event_ticket_waitlist
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_event_host(event_id));
DROP POLICY IF EXISTS "waitlist_insert" ON public.event_ticket_waitlist;
CREATE POLICY "waitlist_insert" ON public.event_ticket_waitlist
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "waitlist_delete" ON public.event_ticket_waitlist;
CREATE POLICY "waitlist_delete" ON public.event_ticket_waitlist
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Audit: hosts only.
DROP POLICY IF EXISTS "ticket_audit_select" ON public.event_ticket_audit;
CREATE POLICY "ticket_audit_select" ON public.event_ticket_audit
  FOR SELECT TO authenticated USING (public.is_event_host(event_id));

-- ---------------------------------------------------------------------------
-- 4. Inventory (public read)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_event_ticket_inventory(UUID);
CREATE OR REPLACE FUNCTION public.get_event_ticket_inventory(p_event_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tiers JSONB;
  v_capacity INTEGER;
  v_sold INTEGER;
  v_waitlist INTEGER;
BEGIN
  SELECT COALESCE(jsonb_agg(t ORDER BY t_sort, t_name), '[]'::jsonb)
  INTO v_tiers
  FROM (
    SELECT
      jsonb_build_object(
        'id', tt.id,
        'name', tt.name,
        'description', tt.description,
        'price', tt.price_kwacha,
        'quantity_total', tt.quantity_total,
        'quantity_sold', tt.quantity_sold,
        'remaining', CASE WHEN tt.quantity_total IS NULL THEN NULL
                          ELSE GREATEST(tt.quantity_total - tt.quantity_sold, 0) END,
        'max_per_order', tt.max_per_order,
        'sales_start', tt.sales_start,
        'sales_end', tt.sales_end,
        'sort_order', tt.sort_order,
        'is_active', tt.is_active,
        'sales_open', (tt.is_active
                        AND (tt.sales_start IS NULL OR now() >= tt.sales_start)
                        AND (tt.sales_end IS NULL OR now() <= tt.sales_end)
                        AND (tt.quantity_total IS NULL OR tt.quantity_sold < tt.quantity_total))
      ) AS t,
      tt.sort_order AS t_sort,
      tt.name AS t_name
    FROM public.event_ticket_tiers tt
    WHERE tt.event_id = p_event_id
  ) sub;

  SELECT COALESCE(SUM(quantity_total), 0), COALESCE(SUM(quantity_sold), 0)
  INTO v_capacity, v_sold
  FROM public.event_ticket_tiers WHERE event_id = p_event_id;

  SELECT COUNT(*) INTO v_waitlist
  FROM public.event_ticket_waitlist WHERE event_id = p_event_id;

  RETURN jsonb_build_object(
    'event_id', p_event_id,
    'tiers', v_tiers,
    'capacity', v_capacity,
    'sold', v_sold,
    'remaining', GREATEST(v_capacity - v_sold, 0),
    'sold_out', (v_capacity > 0 AND v_sold >= v_capacity),
    'waitlist_count', v_waitlist
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_event_ticket_inventory(UUID) FROM anon;

-- ---------------------------------------------------------------------------
-- 5. Reserve (atomic, server-enforced inventory)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.reserve_event_tickets(UUID, UUID, INTEGER, TEXT);
CREATE OR REPLACE FUNCTION public.reserve_event_tickets(
  p_event_id UUID,
  p_tier_id  UUID,
  p_quantity INTEGER,
  p_payment_ref TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_tier public.event_ticket_tiers%ROWTYPE;
  v_event public.events%ROWTYPE;
  v_total NUMERIC(12,2);
  v_paid BOOLEAN := FALSE;
  v_pay_status TEXT;
  v_pay_amount NUMERIC(12,2);
  v_existing public.event_ticket_orders%ROWTYPE;
  v_order_id UUID;
  v_order_ref TEXT;
  v_order_status TEXT;
  v_tickets JSONB := '[]'::jsonb;
  v_i INTEGER;
  v_code TEXT;
  v_now TIMESTAMPTZ := now();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_quantity IS NULL OR p_quantity < 1 THEN RAISE EXCEPTION 'invalid_quantity'; END IF;

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'event_not_found'; END IF;

  -- Idempotency: the same payment ref must never double-book.
  IF p_payment_ref IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.event_ticket_orders
      WHERE payment_ref = p_payment_ref LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object('success', TRUE, 'duplicate', TRUE,
        'order_id', v_existing.id, 'order_ref', v_existing.order_ref,
        'status', v_existing.status);
    END IF;
  END IF;

  -- Lock the tier row so concurrent buyers cannot oversell.
  SELECT * INTO v_tier FROM public.event_ticket_tiers
    WHERE id = p_tier_id AND event_id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'tier_not_found'; END IF;
  IF NOT v_tier.is_active THEN RAISE EXCEPTION 'tier_inactive'; END IF;
  IF v_tier.sales_start IS NOT NULL AND v_now < v_tier.sales_start THEN RAISE EXCEPTION 'sales_not_started'; END IF;
  IF v_tier.sales_end IS NOT NULL AND v_now > v_tier.sales_end THEN RAISE EXCEPTION 'sales_closed'; END IF;
  IF v_tier.max_per_order IS NOT NULL AND p_quantity > v_tier.max_per_order THEN
    RAISE EXCEPTION 'max_per_order_exceeded';
  END IF;
  IF v_tier.quantity_total IS NOT NULL
     AND (v_tier.quantity_total - v_tier.quantity_sold) < p_quantity THEN
    RAISE EXCEPTION 'sold_out';
  END IF;

  v_total := v_tier.price_kwacha * p_quantity;

  IF v_total > 0 THEN
    IF p_payment_ref IS NULL THEN RAISE EXCEPTION 'payment_required'; END IF;
    -- Anchor on the pre-created coa_payments row (buyer + ref). The amount is
    -- re-derived server-side; a client cannot under-declare it.
    SELECT status, amount INTO v_pay_status, v_pay_amount
      FROM public.coa_payments
      WHERE payment_ref = p_payment_ref AND user_id = v_uid
      ORDER BY created_at DESC LIMIT 1;
    IF v_pay_status IS NULL THEN RAISE EXCEPTION 'payment_not_found'; END IF;
    IF v_pay_status IN ('failed','rejected','cancelled') THEN RAISE EXCEPTION 'payment_failed'; END IF;
    IF v_pay_amount IS NULL OR v_pay_amount < v_total THEN RAISE EXCEPTION 'payment_amount_mismatch'; END IF;
    v_paid := v_pay_status IN ('approved','completed','confirmed','settled','paid');
  ELSE
    v_paid := TRUE;
  END IF;

  v_order_status := CASE WHEN v_paid THEN 'paid' ELSE 'pending' END;
  v_order_ref := public.new_order_ref();

  INSERT INTO public.event_ticket_orders
    (order_ref, event_id, tenant_id, buyer_id, tier_id, quantity, unit_price,
     total_amount, status, payment_ref, paid_at)
  VALUES
    (v_order_ref, p_event_id, v_event.tenant_id, v_uid, p_tier_id, p_quantity,
     v_tier.price_kwacha, v_total, v_order_status, p_payment_ref,
     CASE WHEN v_paid THEN v_now END)
  RETURNING id INTO v_order_id;

  FOR v_i IN 1..p_quantity LOOP
    v_code := public.new_ticket_code();
    INSERT INTO public.event_tickets
      (order_id, event_id, tier_id, tenant_id, owner_id, ticket_code, status)
    VALUES
      (v_order_id, p_event_id, p_tier_id, v_event.tenant_id, v_uid, v_code,
       CASE WHEN v_paid THEN 'valid' ELSE 'pending' END);
    v_tickets := v_tickets || to_jsonb(v_code);
  END LOOP;

  UPDATE public.event_ticket_tiers
    SET quantity_sold = quantity_sold + p_quantity, updated_at = v_now
    WHERE id = p_tier_id;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (v_uid,
          'Tickets confirmed: ' || COALESCE(v_event.title, 'Event'),
          p_quantity || ' ticket(s) reserved. Show the QR code at the entrance.',
          'event', p_event_id);

  RETURN jsonb_build_object(
    'success', TRUE, 'duplicate', FALSE, 'order_id', v_order_id,
    'order_ref', v_order_ref, 'status', v_order_status, 'total', v_total,
    'quantity', p_quantity, 'tickets', v_tickets);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reserve_event_tickets(UUID, UUID, INTEGER, TEXT) FROM anon;

-- Confirm pending orders when the anchor payment settles.
CREATE OR REPLACE FUNCTION public.confirm_ticket_order_by_payment(p_payment_ref TEXT)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
BEGIN
  IF p_payment_ref IS NULL THEN RETURN 0; END IF;
  FOR r IN
    SELECT id FROM public.event_ticket_orders
    WHERE payment_ref = p_payment_ref AND status = 'pending'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.event_ticket_orders
      SET status = 'paid', paid_at = now(), updated_at = now()
      WHERE id = r.id;
    UPDATE public.event_tickets
      SET status = 'valid'
      WHERE order_id = r.id AND status = 'pending';
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.confirm_ticket_order_by_payment(TEXT) FROM anon;

CREATE OR REPLACE FUNCTION public.coa_payments_confirm_ticket_orders()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status IN ('approved','completed','confirmed','settled')
     AND (OLD.status IS DISTINCT FROM NEW.status) THEN
    PERFORM public.confirm_ticket_order_by_payment(NEW.payment_ref);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;   -- fee/ticket bookkeeping must never break a payment write
END;
$$;
DROP TRIGGER IF EXISTS trg_coa_payments_confirm_ticket_orders ON public.coa_payments;
CREATE TRIGGER trg_coa_payments_confirm_ticket_orders
  AFTER UPDATE OF status ON public.coa_payments
  FOR EACH ROW EXECUTE FUNCTION public.coa_payments_confirm_ticket_orders();

-- ---------------------------------------------------------------------------
-- 6. Validate / check-in (idempotent, host-only)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.validate_event_ticket(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.validate_event_ticket(
  p_event_id UUID,
  p_ticket_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_t public.event_tickets%ROWTYPE;
  v_name TEXT;
  v_prev TIMESTAMPTZ;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.is_event_host(p_event_id) THEN RAISE EXCEPTION 'not_event_host'; END IF;

  SELECT * INTO v_t FROM public.event_tickets
    WHERE ticket_code = btrim(p_ticket_code) AND event_id = p_event_id
    FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.event_ticket_audit (event_id, action, status, detail, actor_id)
    VALUES (p_event_id, 'check_in', 'invalid', 'code=' || p_ticket_code, v_uid);
    RETURN jsonb_build_object('status', 'invalid',
      'message', 'This ticket is not valid for this event.');
  END IF;

  SELECT COALESCE(full_name, 'Attendee') INTO v_name
    FROM public.profiles WHERE id = v_t.owner_id;

  IF v_t.status = 'used' THEN
    INSERT INTO public.event_ticket_audit (event_id, ticket_id, action, status, detail, actor_id)
    VALUES (p_event_id, v_t.id, 'check_in', 'duplicate',
            v_name || ' already checked in', v_uid);
    RETURN jsonb_build_object('status', 'already_used',
      'message', v_name || ' has already been checked in.',
      'attendee_name', v_name, 'ticket_code', v_t.ticket_code,
      'checked_in_at', v_t.checked_in_at);
  END IF;

  IF v_t.status <> 'valid' THEN
    INSERT INTO public.event_ticket_audit (event_id, ticket_id, action, status, detail, actor_id)
    VALUES (p_event_id, v_t.id, 'check_in', 'invalid',
            'status=' || v_t.status, v_uid);
    RETURN jsonb_build_object('status', 'invalid',
      'message', 'Ticket is ' || v_t.status || ' and cannot be admitted.',
      'attendee_name', v_name, 'ticket_code', v_t.ticket_code);
  END IF;

  UPDATE public.event_tickets
    SET status = 'used', checked_in_at = now(), checked_in_by = v_uid
    WHERE id = v_t.id;

  INSERT INTO public.event_ticket_audit (event_id, ticket_id, action, status, detail, actor_id)
  VALUES (p_event_id, v_t.id, 'check_in', 'valid', v_name || ' checked in', v_uid);

  RETURN jsonb_build_object('status', 'valid',
    'message', v_name || ' checked in successfully.',
    'attendee_name', v_name, 'ticket_code', v_t.ticket_code,
    'checked_in_at', now());
END;
$$;
REVOKE EXECUTE ON FUNCTION public.validate_event_ticket(UUID, TEXT) FROM anon;

-- ---------------------------------------------------------------------------
-- 7. Refund (host-initiated, server-derived amount, ledger-backed)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.refund_event_ticket(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.refund_event_ticket(
  p_ticket_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_t public.event_tickets%ROWTYPE;
  v_o public.event_ticket_orders%ROWTYPE;
  v_open INTEGER;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_t FROM public.event_tickets WHERE id = p_ticket_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
  IF NOT public.is_event_host(v_t.event_id) THEN RAISE EXCEPTION 'not_event_host'; END IF;
  IF v_t.status IN ('refunded','cancelled') THEN RAISE EXCEPTION 'already_refunded'; END IF;

  SELECT * INTO v_o FROM public.event_ticket_orders WHERE id = v_t.order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;

  UPDATE public.event_tickets SET status = 'refunded' WHERE id = v_t.id;

  -- Amount is always the order's unit price — never a client-supplied value.
  INSERT INTO public.event_ticket_refunds
    (ticket_id, order_id, event_id, amount, reason, status, processed_by, refund_ref)
  VALUES
    (v_t.id, v_o.id, v_t.event_id, v_o.unit_price, p_reason, 'completed', v_uid,
     'COA-REF-' || to_char(now(),'YYYY') || '-' ||
     upper(substr(md5(random()::text || clock_timestamp()::text),1,6)));

  SELECT COUNT(*) INTO v_open FROM public.event_tickets
    WHERE order_id = v_o.id AND status NOT IN ('refunded','cancelled','transferred');
  IF v_open = 0 THEN
    UPDATE public.event_ticket_orders
      SET status = 'refunded', refunded_at = now(), updated_at = now()
      WHERE id = v_o.id;
  END IF;

  INSERT INTO public.event_ticket_audit (event_id, ticket_id, action, status, detail, actor_id)
  VALUES (v_t.event_id, v_t.id, 'refund', 'success',
          'refunded ' || v_o.unit_price || ' — ' || COALESCE(p_reason, 'host refund'), v_uid);

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (v_t.owner_id, 'Ticket refunded',
          'A ticket for your order ' || v_o.order_ref || ' was refunded (' ||
          v_o.unit_price || ' ZMW).', 'event', v_t.event_id);

  RETURN jsonb_build_object('success', TRUE, 'ticket_id', v_t.id,
    'amount', v_o.unit_price, 'status', 'refunded');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.refund_event_ticket(UUID, TEXT) FROM anon;

-- ---------------------------------------------------------------------------
-- 8. Transfer (owner-initiated)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.transfer_event_ticket(UUID, UUID);
CREATE OR REPLACE FUNCTION public.transfer_event_ticket(
  p_ticket_id UUID,
  p_to_user UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_t public.event_tickets%ROWTYPE;
  v_code TEXT;
  v_new_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_to_user IS NULL OR p_to_user = v_uid THEN RAISE EXCEPTION 'invalid_recipient'; END IF;

  SELECT * INTO v_t FROM public.event_tickets WHERE id = p_ticket_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ticket_not_found'; END IF;
  IF v_t.owner_id <> v_uid THEN RAISE EXCEPTION 'not_ticket_owner'; END IF;
  IF v_t.status <> 'valid' THEN RAISE EXCEPTION 'ticket_not_transferable'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_to_user) THEN
    RAISE EXCEPTION 'recipient_not_found';
  END IF;

  v_code := public.new_ticket_code();
  INSERT INTO public.event_tickets
    (order_id, event_id, tier_id, tenant_id, owner_id, ticket_code, status)
  VALUES
    (v_t.order_id, v_t.event_id, v_t.tier_id, v_t.tenant_id, p_to_user, v_code, 'valid')
  RETURNING id INTO v_new_id;

  UPDATE public.event_tickets
    SET status = 'transferred', transferred_to = p_to_user, transferred_at = now()
    WHERE id = v_t.id;

  INSERT INTO public.event_ticket_audit (event_id, ticket_id, action, status, detail, actor_id)
  VALUES (v_t.event_id, v_t.id, 'transfer', 'success',
          'transferred to ' || p_to_user, v_uid);

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (p_to_user, 'A ticket was transferred to you',
          'You received a ticket. Open My Tickets to view it.', 'event', v_t.event_id);

  RETURN jsonb_build_object('success', TRUE, 'new_ticket_id', v_new_id,
    'new_ticket_code', v_code, 'status', 'valid');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.transfer_event_ticket(UUID, UUID) FROM anon;

-- ---------------------------------------------------------------------------
-- 9. Event cancellation + waitlist
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.cancel_event_tickets(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.cancel_event_tickets(
  p_event_id UUID,
  p_reason TEXT DEFAULT 'Event cancelled'
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_refunded INTEGER := 0;
  v_cancelled INTEGER := 0;
  r RECORD;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.is_event_host(p_event_id) THEN RAISE EXCEPTION 'not_event_host'; END IF;

  FOR r IN
    SELECT t.id, t.order_id, t.owner_id, o.unit_price, o.status AS order_status
    FROM public.event_tickets t
    JOIN public.event_ticket_orders o ON o.id = t.order_id
    WHERE t.event_id = p_event_id AND t.status IN ('valid','pending')
    FOR UPDATE
  LOOP
    UPDATE public.event_tickets SET status = 'cancelled' WHERE id = r.id;
    v_cancelled := v_cancelled + 1;
    IF r.unit_price > 0 THEN
      INSERT INTO public.event_ticket_refunds
        (ticket_id, order_id, event_id, amount, reason, status, processed_by, refund_ref)
      VALUES (r.id, r.order_id, p_event_id, r.unit_price, p_reason, 'completed', v_uid,
        'COA-REF-' || to_char(now(),'YYYY') || '-' ||
        upper(substr(md5(random()::text || clock_timestamp()::text),1,6)));
      v_refunded := v_refunded + 1;
    END IF;
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (r.owner_id, 'Event cancelled',
            'Your ticket was cancelled. ' ||
            CASE WHEN r.unit_price > 0 THEN 'A refund of ' || r.unit_price || ' ZMW is being processed.'
                 ELSE '' END, 'event', p_event_id);
  END LOOP;

  UPDATE public.event_ticket_orders
    SET status = 'cancelled', updated_at = now()
    WHERE event_id = p_event_id AND status IN ('pending','paid');

  INSERT INTO public.event_ticket_audit (event_id, action, status, detail, actor_id)
  VALUES (p_event_id, 'cancel', 'success',
          v_cancelled || ' tickets cancelled / ' || v_refunded || ' refunded', v_uid);

  RETURN jsonb_build_object('success', TRUE, 'cancelled', v_cancelled,
    'refunded', v_refunded);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.cancel_event_tickets(UUID, TEXT) FROM anon;

DROP FUNCTION IF EXISTS public.join_event_waitlist(UUID, UUID);
CREATE OR REPLACE FUNCTION public.join_event_waitlist(
  p_event_id UUID,
  p_tier_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  INSERT INTO public.event_ticket_waitlist (event_id, tier_id, user_id)
  VALUES (p_event_id, p_tier_id, v_uid)
  ON CONFLICT (event_id, user_id) DO NOTHING;
  RETURN jsonb_build_object('success', TRUE, 'status', 'waitlisted');
END;
$$;
REVOKE EXECUTE ON FUNCTION public.join_event_waitlist(UUID, UUID) FROM anon;

-- ---------------------------------------------------------------------------
-- 10. Backfill: every existing event gets a default tier from ticket_price
-- ---------------------------------------------------------------------------
INSERT INTO public.event_ticket_tiers
  (event_id, tenant_id, name, price_kwacha, quantity_total, is_active, sort_order)
SELECT e.id, e.tenant_id, 'General Admission', COALESCE(e.ticket_price, 0),
       e.max_capacity, TRUE, 0
FROM public.events e
WHERE NOT EXISTS (
  SELECT 1 FROM public.event_ticket_tiers t WHERE t.event_id = e.id
);
