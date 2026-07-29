-- Fix: Enable RLS on id_sequences table
-- id_sequences is only used by SECURITY DEFINER RPC functions (next_id_sequence),
-- so no direct user access is needed. Enable RLS + deny all direct access.

ALTER TABLE public.id_sequences ENABLE ROW LEVEL SECURITY;

-- No SELECT/INSERT/UPDATE/DELETE policies = all direct access denied
-- The next_id_sequence() RPC function uses SECURITY DEFINER to bypass RLS
