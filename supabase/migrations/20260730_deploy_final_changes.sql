-- Deploy final fixes: job applications UNIQUE, job promoter role, event_checkins, driver_applications

-- 1. JOB APPLICATIONS - Remove duplicates then add UNIQUE constraint
DELETE FROM public.job_applications
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY job_id, applicant_id ORDER BY created_at ASC) AS rn
        FROM public.job_applications
    ) dup WHERE dup.rn > 1
);
ALTER TABLE IF EXISTS public.job_applications DROP CONSTRAINT IF EXISTS job_applications_job_id_applicant_id_key;
ALTER TABLE IF EXISTS public.job_applications ADD CONSTRAINT job_applications_job_id_applicant_id_key UNIQUE (job_id, applicant_id);

-- 2. DRIVER APPLICATIONS - Ensure table exists
CREATE TABLE IF NOT EXISTS public.driver_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone_number TEXT NOT NULL,
    email TEXT,
    vehicle_type TEXT,
    license_number TEXT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES auth.users(id),
    notes TEXT,
    UNIQUE(user_id)
);

-- 3. EVENT CHECKINS - Ensure table exists
CREATE TABLE IF NOT EXISTS public.event_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    registration_id UUID NOT NULL REFERENCES public.event_registrations(id) ON DELETE CASCADE,
    scanned_by UUID NOT NULL REFERENCES auth.users(id),
    scanned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    scan_method TEXT DEFAULT 'qr_code',
    device_info TEXT,
    UNIQUE(registration_id)
);

-- 4. PROFILE ROLE CHECK - Add job_promoter, praise_team, praise_team_leader
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
EXCEPTION WHEN others THEN NULL;
END $$;

-- 5. RLS POLICIES for job_applications
ALTER TABLE IF EXISTS public.job_applications ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    DROP POLICY IF EXISTS "job_applications_select_own" ON public.job_applications;
    CREATE POLICY "job_applications_select_own" ON public.job_applications
        FOR SELECT USING (auth.uid() = applicant_id);
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$
BEGIN
    DROP POLICY IF EXISTS "job_applications_insert_own" ON public.job_applications;
    CREATE POLICY "job_applications_insert_own" ON public.job_applications
        FOR INSERT WITH CHECK (auth.uid() = applicant_id);
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$
BEGIN
    DROP POLICY IF EXISTS "job_applications_select_admin" ON public.job_applications;
    CREATE POLICY "job_applications_select_admin" ON public.job_applications
        FOR SELECT USING (
            EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin', 'job_promoter', 'pastor', 'bishop'))
        );
EXCEPTION WHEN others THEN NULL;
END $$;

-- 6. RLS POLICIES for event_checkins
ALTER TABLE IF EXISTS public.event_checkins ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    DROP POLICY IF EXISTS "event_checkins_select_event_host" ON public.event_checkins;
    CREATE POLICY "event_checkins_select_event_host" ON public.event_checkins
        FOR SELECT USING (
            EXISTS (SELECT 1 FROM events WHERE id = event_id AND created_by = auth.uid())
        );
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$
BEGIN
    DROP POLICY IF EXISTS "event_checkins_insert_scanner" ON public.event_checkins;
    CREATE POLICY "event_checkins_insert_scanner" ON public.event_checkins
        FOR INSERT WITH CHECK (scanned_by = auth.uid());
EXCEPTION WHEN others THEN NULL;
END $$;

-- 7. RLS POLICIES for driver_applications
ALTER TABLE IF EXISTS public.driver_applications ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    DROP POLICY IF EXISTS "driver_applications_select_own" ON public.driver_applications;
    CREATE POLICY "driver_applications_select_own" ON public.driver_applications
        FOR SELECT USING (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$
BEGIN
    DROP POLICY IF EXISTS "driver_applications_insert_own" ON public.driver_applications;
    CREATE POLICY "driver_applications_insert_own" ON public.driver_applications
        FOR INSERT WITH CHECK (auth.uid() = user_id);
EXCEPTION WHEN others THEN NULL;
END $$;

-- 8. RECORD EVENT CHECK-IN FUNCTION
CREATE OR REPLACE FUNCTION public.record_event_checkin(
    p_registration_id UUID,
    p_event_id UUID,
    p_scanned_by UUID,
    p_device_info TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- Update registration
    UPDATE public.event_registrations
    SET check_in_status = true, checked_in_at = now(), checked_in_by = p_scanned_by
    WHERE id = p_registration_id;

    -- Insert checkin record
    INSERT INTO public.event_checkins (event_id, registration_id, scanned_by, device_info)
    VALUES (p_event_id, p_registration_id, p_scanned_by, p_device_info)
    ON CONFLICT (registration_id) DO NOTHING;

    v_result := jsonb_build_object('success', true, 'registration_id', p_registration_id);
    RETURN v_result;
END;
$$;

-- 9. INCREMENT ATTENDEE COUNT FUNCTION (if missing)
DROP FUNCTION IF EXISTS public.increment_attendee_count;
CREATE OR REPLACE FUNCTION public.increment_attendee_count(p_event_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    UPDATE public.events SET attendee_count = COALESCE(attendee_count, 0) + 1 WHERE id = p_event_id;
END;
$$;

-- 10. TICKET_CODE column on event_registrations (if not exists)
ALTER TABLE IF EXISTS public.event_registrations ADD COLUMN IF NOT EXISTS ticket_code TEXT;
