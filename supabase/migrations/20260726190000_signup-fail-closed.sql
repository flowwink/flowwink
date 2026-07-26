-- CRITICAL: self-service signup granted the admin role.
--
-- handle_new_user() resolved the requested role with
--     COALESCE(NEW.raw_user_meta_data ->> 'signup_type', 'admin')
-- so a signup carrying NO metadata became an ADMIN. Measured 2026-07-25:
-- public signup is enabled on all four instances (disable_signup=false) and the
-- anon key ships in the frontend bundle, so a raw supabase.auth.signUp() with no
-- metadata was a self-service route to the admin role. On autoversio, where
-- mailer_autoconfirm is on, it needed no mailbox at all.
--
-- Found while gating the internal ERP tables — the RLS work was pointless while
-- anyone could simply become an admin.
--
-- Every legitimate provisioning path already names its type explicitly:
--   scripts/flowwink.sh          → signup_type 'admin'
--   supabase/functions/invite-employee → 'employee'
--   supabase/functions/customer-signup → 'customer'
-- so nothing depends on the default. It only ever served the case nobody should
-- reach. The default now fails CLOSED to the least-privileged role.
--
-- 'employee' keeps mapping to writer, which is what it did before via the ELSE
-- branch; that branch is the other half of the bug — an unrecognised type also
-- fell through to a content-writing role, so a typo escalated too.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  signup_type text;
BEGIN
  -- Fail CLOSED. Absent or unrecognised metadata must never imply privilege.
  signup_type := COALESCE(NEW.raw_user_meta_data ->> 'signup_type', 'customer');

  INSERT INTO public.profiles (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.email)
  )
  ON CONFLICT (id) DO NOTHING;

  IF signup_type = 'admin' THEN
    -- Reached only when a provisioning path asks for it by name.
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'admin')
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSIF signup_type = 'employee' THEN
    -- Preserves the previous behaviour of the ELSE branch for invite-employee.
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'writer')
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    -- 'customer', anything unrecognised, and anything absent.
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'customer')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Assigns the initial role at signup. FAILS CLOSED: only an explicit '
  'signup_type of ''admin'' grants admin. Absent or unrecognised metadata '
  'yields customer — the least-privileged role — because public signup is '
  'reachable with the anon key that ships in the frontend bundle.';
