-- The signature page has never worked for the person it was built for.
--
-- /contract/:token is the last step of the sales chain and the only one a
-- CUSTOMER touches. usePublicContract read the contracts table directly with
-- the anon key — and contracts has exactly one SELECT policy, for
-- authenticated users. So an anonymous counterparty following a signing link
-- got "Contract not found" on every instance in the fleet. Sending a contract
-- for signature looked like it worked; only the recipient ever saw the failure,
-- and they would assume the link had expired.
--
-- The fix must not open the table. An anon policy wide enough to serve the page
-- (accept_token IS NOT NULL AND status = 'pending_signature') would expose
-- every outstanding agreement to anyone with the publishable key. Instead the
-- token is the key: a SECURITY DEFINER function that returns exactly one row,
-- and only to a caller who already holds its 32-byte token.

-- REPLAY GUARD (2026-08-13): this is an EARLY definition of get_public_contract.
-- Replaying it onto an instance that already carries a LATER one (different
-- OUT columns, e.g. the appendices version) is 42P13 at best and a silent
-- downgrade at worst — found when the GitHub-integration deploy replayed
-- ledger holes on the fleet. Skip when the function exists; from zero the
-- normal order creates here and upgrades later.
DO $guard$ BEGIN
  IF to_regprocedure('public.get_public_contract(text)') IS NULL THEN
    EXECUTE $create$
CREATE OR REPLACE FUNCTION public.get_public_contract(p_token text)
RETURNS TABLE (
  id uuid,
  title text,
  counterparty_name text,
  counterparty_email text,
  status public.contract_status,
  body_markdown text,
  signed_at timestamptz,
  version integer,
  currency text,
  value_cents bigint,
  start_date date,
  end_date date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.id, c.title, c.counterparty_name, c.counterparty_email, c.status,
         c.body_markdown, c.signed_at, c.version, c.currency, c.value_cents,
         c.start_date, c.end_date
  FROM public.contracts c
  -- Length guard: a short or empty token can never be a real one, and without
  -- it an empty string would match every row with a NULL-free token column.
  WHERE length(coalesce(trim(p_token), '')) >= 16
    AND c.accept_token = trim(p_token)
  LIMIT 1;
$$
    $create$;
  END IF;
END $guard$;

-- Deliberately anon-callable: this IS the public surface. The token is the
-- credential, the same way ingest_form_lead is the one anon-callable write.
GRANT EXECUTE ON FUNCTION public.get_public_contract(text) TO anon, authenticated, service_role;
