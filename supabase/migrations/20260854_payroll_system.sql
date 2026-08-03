-- ============================================================
-- PAYROLL SYSTEM: employees, payroll_runs, payslips
-- Zambian statutory: PAYE (progressive), NAPSA (5%+5% capped), 
-- NHIMA (1%+1%), SDL (0.5% employer), tax-free threshold K4,500
-- ============================================================

-- 1. Employees table — extends profiles with payroll data
CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  role_title TEXT NOT NULL DEFAULT 'employee',
  department TEXT DEFAULT 'general',
  employment_date DATE,
  employment_type TEXT DEFAULT 'full_time', -- full_time, part_time, contract, casual
  gross_salary NUMERIC NOT NULL DEFAULT 0,
  allowances NUMERIC DEFAULT 0, -- housing, transport, meal allowances
  benefits_in_kind NUMERIC DEFAULT 0, -- non-cash benefits (company car, etc.)
  napsa_number TEXT,
  nhima_number TEXT,
  tax_reference TEXT,
  bank_name TEXT,
  bank_account TEXT,
  payment_method TEXT DEFAULT 'mobile_money', -- mobile_money, bank, cash
  mobile_number TEXT,
  network TEXT, -- mtn, airtel, zamtel
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Payroll runs — monthly batch processing
CREATE TABLE IF NOT EXISTS public.payroll_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  period_month INT NOT NULL, -- 1-12
  period_year INT NOT NULL,
  status TEXT DEFAULT 'draft', -- draft, processed, paid, filed
  total_gross NUMERIC DEFAULT 0,
  total_paye NUMERIC DEFAULT 0,
  total_napsa_employee NUMERIC DEFAULT 0,
  total_napsa_employer NUMERIC DEFAULT 0,
  total_nhima_employee NUMERIC DEFAULT 0,
  total_nhima_employer NUMERIC DEFAULT 0,
  total_sdl NUMERIC DEFAULT 0,
  total_net_pay NUMERIC DEFAULT 0,
  employee_count INT DEFAULT 0,
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Payslips — individual employee payslips per payroll run
CREATE TABLE IF NOT EXISTS public.payslips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_run_id UUID REFERENCES public.payroll_runs(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE CASCADE,
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE,
  
  -- Earnings
  basic_salary NUMERIC NOT NULL DEFAULT 0,
  allowances NUMERIC DEFAULT 0,
  benefits_in_kind NUMERIC DEFAULT 0,
  gross_salary NUMERIC NOT NULL DEFAULT 0,
  
  -- Statutory deductions (employee)
  paye NUMERIC DEFAULT 0,
  napsa_employee NUMERIC DEFAULT 0,
  nhima_employee NUMERIC DEFAULT 0,
  
  -- Employer contributions (not deducted from employee, but tracked)
  napsa_employer NUMERIC DEFAULT 0,
  nhima_employer NUMERIC DEFAULT 0,
  sdl NUMERIC DEFAULT 0,
  
  -- Net
  total_deductions NUMERIC DEFAULT 0,
  net_pay NUMERIC NOT NULL DEFAULT 0,
  
  -- Metadata
  tax_breakdown JSONB DEFAULT '{}', -- stores detailed PAYE band breakdown
  status TEXT DEFAULT 'draft', -- draft, finalized, paid
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. ZRA tax bands — configurable progressive tax rates
CREATE TABLE IF NOT EXISTS public.tax_bands (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_name TEXT NOT NULL,
  min_amount NUMERIC NOT NULL,
  max_amount NUMERIC, -- NULL = no upper limit
  rate NUMERIC NOT NULL, -- decimal, e.g. 0.25 = 25%
  fixed_amount NUMERIC DEFAULT 0, -- cumulative tax from previous bands
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Payroll settings per tenant
CREATE TABLE IF NOT EXISTS public.payroll_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES public.churches(id) ON DELETE CASCADE UNIQUE,
  tax_free_threshold NUMERIC DEFAULT 4500, -- K4,500/month (K54,000/year)
  napsa_cap NUMERIC DEFAULT 1861.80, -- K1,861.80/month
  sdl_threshold INT DEFAULT 5, -- SDL applies if 5+ employees
  sdl_rate NUMERIC DEFAULT 0.005, -- 0.5%
  paye_rates JSONB DEFAULT '[
    {"min": 0, "max": 4500, "rate": 0, "label": "Tax-free"},
    {"min": 4501, "max": 6800, "rate": 0.20, "label": "20%"},
    {"min": 6801, "max": 9800, "rate": 0.25, "label": "25%"},
    {"min": 9801, "max": 14500, "rate": 0.30, "label": "30%"},
    {"min": 14501, "max": null, "rate": 0.35, "label": "35%"}
  ]',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 6. Indexes
CREATE INDEX IF NOT EXISTS idx_employees_tenant ON public.employees(tenant_id);
CREATE INDEX IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS idx_payroll_runs_tenant ON public.payroll_runs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_payroll_runs_period ON public.payroll_runs(period_year, period_month);
CREATE INDEX IF NOT EXISTS idx_payslips_run ON public.payslips(payroll_run_id);
CREATE INDEX IF NOT EXISTS idx_payslips_employee ON public.payslips(employee_id);
CREATE INDEX IF NOT EXISTS idx_payslips_tenant ON public.payslips(tenant_id);

-- 7. Seed ZRA 2026 tax bands
INSERT INTO public.tax_bands (band_name, min_amount, max_amount, rate, fixed_amount) VALUES
  ('Tax-Free Threshold', 0, 4500, 0, 0),
  ('Band 1', 4501, 6800, 0.20, 0),
  ('Band 2', 6801, 9800, 0.25, 460),
  ('Band 3', 9801, 14500, 0.30, 1210),
  ('Band 4', 14501, NULL, 0.35, 2620)
ON CONFLICT DO NOTHING;

-- 8. RLS policies
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payslips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tax_bands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_settings ENABLE ROW LEVEL SECURITY;

-- Employees: tenant-scoped
DO $$ BEGIN
  DROP POLICY IF EXISTS "Tenant admins manage employees" ON public.employees;
  DROP POLICY IF EXISTS "Superadmins full access employees" ON public.employees;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Tenant admins manage employees" ON public.employees
  FOR ALL USING (
    tenant_id::text IN (
      SELECT tenant_id FROM public.profiles WHERE id = auth.uid()
      AND role IN ('pastor', 'bishop', 'admin', 'superadmin', 'coa_employee')
    )
  );

CREATE POLICY "Superadmins full access employees" ON public.employees
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee'))
  );

-- Payroll runs: tenant-scoped
DO $$ BEGIN
  DROP POLICY IF EXISTS "Tenant admins manage payroll_runs" ON public.payroll_runs;
  DROP POLICY IF EXISTS "Superadmins full access payroll_runs" ON public.payroll_runs;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Tenant admins manage payroll_runs" ON public.payroll_runs
  FOR ALL USING (
    tenant_id::text IN (
      SELECT tenant_id FROM public.profiles WHERE id = auth.uid()
      AND role IN ('pastor', 'bishop', 'admin', 'superadmin', 'coa_employee')
    )
  );

CREATE POLICY "Superadmins full access payroll_runs" ON public.payroll_runs
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee'))
  );

-- Payslips: tenant-scoped
DO $$ BEGIN
  DROP POLICY IF EXISTS "Tenant admins manage payslips" ON public.payslips;
  DROP POLICY IF EXISTS "Superadmins full access payslips" ON public.payslips;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Tenant admins manage payslips" ON public.payslips
  FOR ALL USING (
    tenant_id::text IN (
      SELECT tenant_id FROM public.profiles WHERE id = auth.uid()
      AND role IN ('pastor', 'bishop', 'admin', 'superadmin', 'coa_employee')
    )
  );

CREATE POLICY "Superadmins full access payslips" ON public.payslips
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'coa_employee'))
  );

-- Tax bands: read-only for everyone, write for superadmin
DO $$ BEGIN
  DROP POLICY IF EXISTS "Anyone can read tax_bands" ON public.tax_bands;
  DROP POLICY IF EXISTS "Superadmins manage tax_bands" ON public.tax_bands;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Anyone can read tax_bands" ON public.tax_bands FOR SELECT USING (true);
CREATE POLICY "Superadmins manage tax_bands" ON public.tax_bands
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'superadmin')
  );

-- Payroll settings: tenant-scoped
DO $$ BEGIN
  DROP POLICY IF EXISTS "Tenant admins manage payroll_settings" ON public.payroll_settings;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;
CREATE POLICY "Tenant admins manage payroll_settings" ON public.payroll_settings
  FOR ALL USING (
    tenant_id::text IN (
      SELECT tenant_id FROM public.profiles WHERE id = auth.uid()
      AND role IN ('pastor', 'bishop', 'admin', 'superadmin', 'coa_employee')
    )
  );

-- 9. RPC: Calculate PAYE given gross salary (returns breakdown)
CREATE OR REPLACE FUNCTION calculate_paye(gross_salary NUMERIC)
RETURNS JSONB AS $$
DECLARE
  taxable NUMERIC := 0;
  total_tax NUMERIC := 0;
  band RECORD;
  band_tax NUMERIC;
  result JSONB := '[]'::JSONB;
  threshold NUMERIC := 4500;
BEGIN
  taxable := gross_salary - threshold;
  IF taxable <= 0 THEN
    RETURN jsonb_build_array(
      jsonb_build_object('band', 'Tax-Free', 'amount', gross_salary, 'rate', 0, 'tax', 0)
    );
  END IF;

  FOR band IN 
    SELECT * FROM tax_bands WHERE is_active = true AND min_amount > threshold ORDER BY min_amount
  LOOP
    IF taxable <= 0 THEN EXIT; END IF;
    
    DECLARE
      band_width NUMERIC;
      band_amount NUMERIC;
      band_tax_amt NUMERIC;
    BEGIN
      band_width := COALESCE(band.max_amount, 999999999) - band.min_amount + 1;
      band_amount := LEAST(taxable, band_width);
      band_tax_amt := band_amount * band.rate;
      
      total_tax := total_tax + band_tax_amt;
      taxable := taxable - band_amount;
      
      result := result || jsonb_build_array(
        jsonb_build_object(
          'band', band.band_name,
          'amount', band_amount,
          'rate', band.rate * 100,
          'tax', band_tax_amt
        )
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'taxable_income', gross_salary - threshold,
    'total_tax', total_tax,
    'bands', result
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 10. RPC: Process full payroll run for a tenant/month
CREATE OR REPLACE FUNCTION process_payroll(
  p_tenant_id UUID,
  p_month INT,
  p_year INT,
  p_processed_by UUID
)
RETURNS JSONB AS $$
DECLARE
  emp RECORD;
  settings_rec RECORD;
  gross NUMERIC;
  taxable NUMERIC;
  paye NUMERIC := 0;
  napsa_ee NUMERIC := 0;
  napsa_er NUMERIC := 0;
  nhima_ee NUMERIC := 0;
  nhima_er NUMERIC := 0;
  sdl NUMERIC := 0;
  net NUMERIC;
  run_id UUID;
  total_gross NUMERIC := 0;
  total_paye NUMERIC := 0;
  total_napsa_ee NUMERIC := 0;
  total_napsa_er NUMERIC := 0;
  total_nhima_ee NUMERIC := 0;
  total_nhima_er NUMERIC := 0;
  total_sdl NUMERIC := 0;
  total_net NUMERIC := 0;
  emp_count INT := 0;
  band RECORD;
  taxable_remaining NUMERIC;
  band_width NUMERIC;
  band_amount NUMERIC;
  paye_result JSONB;
  band_data JSONB;
BEGIN
  -- Get payroll settings
  SELECT * INTO settings_rec FROM payroll_settings WHERE tenant_id = p_tenant_id;
  IF settings_rec IS NULL THEN
    settings_rec := ROW(NULL, p_tenant_id, 4500, 1861.80, 5, 0.005, 
      '[{"min":0,"max":4500,"rate":0},{"min":4501,"max":6800,"rate":0.20},{"min":6801,"max":9800,"rate":0.25},{"min":9801,"max":14500,"rate":0.30},{"min":14501,"max":null,"rate":0.35}]'::jsonb,
      now(), now());
  END IF;

  -- Create payroll run
  INSERT INTO payroll_runs (tenant_id, period_month, period_year, status, processed_by, processed_at)
  VALUES (p_tenant_id, p_month, p_year, 'processed', p_processed_by, now())
  RETURNING id INTO run_id;

  -- Process each active employee
  FOR emp IN SELECT * FROM employees WHERE tenant_id = p_tenant_id AND is_active = true
  LOOP
    gross := emp.gross_salary + COALESCE(emp.allowances, 0);
    
    -- PAYE (progressive bands)
    taxable := gross - settings_rec.tax_free_threshold;
    paye := 0;
    IF taxable > 0 THEN
      paye_result := calculate_paye(gross);
      paye := (paye_result->>'total_tax')::NUMERIC;
    END IF;

    -- NAPSA (5% employee, 5% employer, capped)
    napsa_ee := LEAST(gross * 0.05, settings_rec.napsa_cap);
    napsa_er := LEAST(gross * 0.05, settings_rec.napsa_cap);

    -- NHIMA (1% employee, 1% employer)
    nhima_ee := gross * 0.01;
    nhima_er := gross * 0.01;

    -- SDL (0.5% employer only, if 5+ employees)
    sdl := 0; -- calculated at run level

    net := gross - paye - napsa_ee - nhima_ee;

    -- Insert payslip
    INSERT INTO payslips (
      payroll_run_id, employee_id, tenant_id,
      basic_salary, allowances, benefits_in_kind, gross_salary,
      paye, napsa_employee, nhima_employee,
      napsa_employer, nhima_employer, sdl,
      total_deductions, net_pay, tax_breakdown, status
    ) VALUES (
      run_id, emp.id, p_tenant_id,
      emp.gross_salary, COALESCE(emp.allowances, 0), COALESCE(emp.benefits_in_kind, 0), gross,
      paye, napsa_ee, nhima_ee,
      napsa_er, nhima_er, 0,
      paye + napsa_ee + nhima_ee, net,
      COALESCE(paye_result, '{}'::jsonb), 'finalized'
    );

    -- Accumulate totals
    total_gross := total_gross + gross;
    total_paye := total_paye + paye;
    total_napsa_ee := total_napsa_ee + napsa_ee;
    total_napsa_er := total_napsa_er + napsa_er;
    total_nhima_ee := total_nhima_ee + nhima_ee;
    total_nhima_er := total_nhima_er + nhima_er;
    total_net := total_net + net;
    emp_count := emp_count + 1;
  END LOOP;

  -- SDL (0.5% of total gross, employer only, if 5+ employees)
  IF emp_count >= settings_rec.sdl_threshold THEN
    sdl := total_gross * settings_rec.sdl_rate;
  END IF;

  -- Update payroll run totals
  UPDATE payroll_runs SET
    total_gross = total_gross,
    total_paye = total_paye,
    total_napsa_employee = total_napsa_ee,
    total_napsa_employer = total_napsa_er,
    total_nhima_employee = total_nhima_ee,
    total_nhima_employer = total_nhima_er,
    total_sdl = sdl,
    total_net_pay = total_net,
    employee_count = emp_count
  WHERE id = run_id;

  -- Update SDL on payslips
  IF sdl > 0 THEN
    UPDATE payslips SET sdl = sdl / emp_count WHERE payroll_run_id = run_id;
  END IF;

  RETURN jsonb_build_object(
    'run_id', run_id,
    'employee_count', emp_count,
    'total_gross', total_gross,
    'total_paye', total_paye,
    'total_napsa_employee', total_napsa_ee,
    'total_napsa_employer', total_napsa_er,
    'total_nhima_employee', total_nhima_ee,
    'total_nhima_employer', total_nhima_er,
    'total_sdl', sdl,
    'total_net_pay', total_net
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
