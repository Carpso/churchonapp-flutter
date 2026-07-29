CREATE OR REPLACE FUNCTION public.set_church_trial()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
    IF NEW.trial_started_at IS NULL THEN
        NEW.trial_started_at := now();
        NEW.trial_ends_at := now() + INTERVAL '30 days';
        NEW.subscription_status := 'trial';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_church_trial_active(church_id UUID)
RETURNS BOOLEAN
SET search_path = public
AS $$
DECLARE
    status TEXT;
    ends_at TIMESTAMPTZ;
BEGIN
    SELECT subscription_status, trial_ends_at INTO status, ends_at
    FROM public.churches WHERE id = church_id;

    IF status = 'active' THEN
        RETURN true;
    END IF;

    IF status = 'trial' AND ends_at IS NOT NULL AND ends_at > now() THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.notify_role_approved()
RETURNS TRIGGER
SET search_path = public
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.notify_writer_approved()
RETURNS TRIGGER
SET search_path = public
AS $$
BEGIN
    IF NEW.status = 'approved' AND (OLD IS NULL OR OLD.status != 'approved') THEN
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.notify_profile_role_change()
RETURNS TRIGGER
SET search_path = public
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
$$ LANGUAGE plpgsql SECURITY DEFINER;
