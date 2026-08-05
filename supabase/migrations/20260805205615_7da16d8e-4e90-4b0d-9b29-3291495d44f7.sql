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
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'admin')
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSIF signup_type = 'employee' THEN
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'writer')
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.id, 'customer')
    ON CONFLICT (user_id, role) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Assigns the initial role at signup. FAILS CLOSED: only an explicit signup_type of ''admin'' grants admin. Absent or unrecognised metadata yields customer.';