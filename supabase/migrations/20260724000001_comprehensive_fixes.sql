-- ============================================================
-- Comprehensive Fixes: event_registrations, jobs, writer_apps
-- ============================================================

-- 1. ENSURE event_registrations EXISTS + ADD rsvp_status
CREATE TABLE IF NOT EXISTS public.event_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    check_in_status BOOLEAN DEFAULT false,
    rsvp_status TEXT DEFAULT 'Going',
    registered_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(event_id, user_id)
);

ALTER TABLE public.event_registrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.event_registrations ADD COLUMN IF NOT EXISTS rsvp_status TEXT DEFAULT 'Going';
ALTER TABLE public.event_registrations ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE public.event_registrations ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

-- RLS policies for event_registrations
DROP POLICY IF EXISTS "Users can view own registrations" ON public.event_registrations;
CREATE POLICY "Users can view own registrations" ON public.event_registrations
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can register for events" ON public.event_registrations;
CREATE POLICY "Users can register for events" ON public.event_registrations
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Event hosts can manage registrations" ON public.event_registrations;
CREATE POLICY "Event hosts can manage registrations" ON public.event_registrations
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.events e WHERE e.id = event_registrations.event_id AND e.user_id = auth.uid())
    );

CREATE INDEX IF NOT EXISTS idx_event_registrations_event ON public.event_registrations(event_id);
CREATE INDEX IF NOT EXISTS idx_event_registrations_user ON public.event_registrations(user_id);

-- 2. ENSURE job_applications TABLE EXISTS
CREATE TABLE IF NOT EXISTS public.job_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES public.jobs(id) ON DELETE CASCADE,
    applicant_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    applicant_name TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'reviewed')),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(job_id, applicant_id)
);

ALTER TABLE public.job_applications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.job_applications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE public.job_applications ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

DROP POLICY IF EXISTS "Users can view own applications" ON public.job_applications;
CREATE POLICY "Users can view own applications" ON public.job_applications
    FOR SELECT TO authenticated USING (auth.uid() = applicant_id);

DROP POLICY IF EXISTS "Employers can view applications for their jobs" ON public.job_applications;
CREATE POLICY "Employers can view applications for their jobs" ON public.job_applications
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM public.jobs j WHERE j.id = job_applications.job_id AND j.user_id = auth.uid())
    );

DROP POLICY IF EXISTS "Users can apply for jobs" ON public.job_applications;
CREATE POLICY "Users can apply for jobs" ON public.job_applications
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = applicant_id);

DROP POLICY IF EXISTS "Employers can update application status" ON public.job_applications;
CREATE POLICY "Employers can update application status" ON public.job_applications
    FOR UPDATE TO authenticated USING (
        EXISTS (SELECT 1 FROM public.jobs j WHERE j.id = job_applications.job_id AND j.user_id = auth.uid())
    );

DROP POLICY IF EXISTS "Superadmins and employees can manage all applications" ON public.job_applications;
CREATE POLICY "Superadmins and employees can manage all applications" ON public.job_applications
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );

-- 3. ENSURE jobs TABLE HAS ALL COLUMNS
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS promoter_id UUID REFERENCES auth.users(id);
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- 4. ENSURE driver_applications TABLE EXISTS
CREATE TABLE IF NOT EXISTS public.driver_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    vehicle_type TEXT,
    license_plate TEXT,
    vehicle_make_model TEXT,
    vehicle_color TEXT,
    vehicle_photo_url TEXT,
    drivers_license_url TEXT,
    national_id_url TEXT,
    payout_operator TEXT,
    payout_number TEXT,
    email TEXT,
    phone TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.driver_applications ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.driver_applications ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id);
ALTER TABLE public.driver_applications ADD COLUMN IF NOT EXISTS church_id UUID REFERENCES public.churches(id);

DROP POLICY IF EXISTS "Users can view own applications" ON public.driver_applications;
CREATE POLICY "Users can view own applications" ON public.driver_applications
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can submit applications" ON public.driver_applications;
CREATE POLICY "Users can submit applications" ON public.driver_applications
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can manage all driver applications" ON public.driver_applications;
CREATE POLICY "Admins can manage all driver applications" ON public.driver_applications
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee', 'admin', 'pastor', 'bishop'))
    );

-- 5. ENSURE ride_registrations has approved_by
ALTER TABLE public.ride_registrations ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);

-- 6. ADD JOB PROMOTER + PRAISE TEAM ROLES TO PROFILE CHECK
DO $$
BEGIN
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check
        CHECK (role IN (
            'member', 'admin', 'pastor', 'bishop', 'superadmin', 'employee',
            'treasurer', 'secretary', 'usher', 'driver', 'rider',
            'vendor', 'merchant', 'bookshop_owner',
            'event_organiser', 'event_organizer', 'event_promoter',
            'bible_quiz_promoter', 'writer',
            'leader', 'general_secretary', 'general_treasurer',
            'prophet', 'apostle', 'assistant_pastor',
            'praise_team', 'praise_team_leader',
            'job_promoter', 'coa_employee'
        ));
EXCEPTION WHEN others THEN
    NULL;
END $$;

-- 7. ENSURE writer_applications TABLE
CREATE TABLE IF NOT EXISTS public.writer_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    email TEXT,
    phone TEXT,
    reason TEXT,
    writing_samples_url TEXT,
    book_file_url TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.writer_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own writer applications" ON public.writer_applications;
CREATE POLICY "Users can view own writer applications" ON public.writer_applications
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can submit writer applications" ON public.writer_applications;
CREATE POLICY "Users can submit writer applications" ON public.writer_applications
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Superadmins and employees can manage writer applications" ON public.writer_applications;
CREATE POLICY "Superadmins and employees can manage writer applications" ON public.writer_applications
    FOR ALL TO authenticated USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role IN ('superadmin', 'employee'))
    );
