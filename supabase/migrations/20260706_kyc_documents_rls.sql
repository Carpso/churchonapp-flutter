-- 1. Create kyc_documents table if not exists
CREATE TABLE IF NOT EXISTS public.kyc_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    document_type TEXT NOT NULL,
    url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    encrypted_key TEXT,
    encryption_iv TEXT,
    reviewed_by UUID REFERENCES auth.users(id),
    review_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kyc_documents ENABLE ROW LEVEL SECURITY;

-- Users can view only their own KYC documents
DROP POLICY IF EXISTS "Users can view own KYC documents" ON public.kyc_documents;
CREATE POLICY "Users can view own KYC documents"
    ON public.kyc_documents FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- Superadmins and employees can view all KYC documents
DROP POLICY IF EXISTS "Admins can view all KYC documents" ON public.kyc_documents;
CREATE POLICY "Admins can view all KYC documents"
    ON public.kyc_documents FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND (role = 'superadmin' OR role = 'employee')
        )
    );

-- Users can insert their own KYC documents
DROP POLICY IF EXISTS "Users can insert own KYC documents" ON public.kyc_documents;
CREATE POLICY "Users can insert own KYC documents"
    ON public.kyc_documents FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Superadmins and employees can update KYC documents (review status)
DROP POLICY IF EXISTS "Admins can update KYC documents" ON public.kyc_documents;
CREATE POLICY "Admins can update KYC documents"
    ON public.kyc_documents FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND (role = 'superadmin' OR role = 'employee')
        )
    );

CREATE INDEX IF NOT EXISTS idx_kyc_documents_user_id ON public.kyc_documents(user_id);
CREATE INDEX IF NOT EXISTS idx_kyc_documents_status ON public.kyc_documents(status);

-- 2. Update profiles kyc_status to use verification_status
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS kyc_status TEXT DEFAULT 'unverified';

-- 3. Enable Realtime for kyc_documents
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_rel pr
    JOIN pg_publication p ON p.oid = pr.prpubid
    JOIN pg_class c ON c.oid = pr.prrelid
    WHERE p.pubname = 'supabase_realtime' AND c.relname = 'kyc_documents'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE kyc_documents;
  END IF;
END $$;
