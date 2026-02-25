CREATE TABLE IF NOT EXISTS public.attendance_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    tenant_id text,
    check_in_time timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now()
);

ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin Read Attendance" ON public.attendance_logs FOR SELECT USING (true);
CREATE POLICY "Auth Insert Attendance" ON public.attendance_logs FOR INSERT WITH CHECK (true);
