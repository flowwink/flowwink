-- site_settings.modules is born with the instance.
--
-- THE SPLIT BRAIN
-- ---------------
-- The client and the server disagreed about what a module row's ABSENCE means.
--
--   • Client (src/hooks/useModules.tsx): `{...defaultModulesSettings, ...stored}`
--     — an absent row merges to the code defaults, so /admin renders a
--     configured product: 7 modules enabled, nav populated, module cards green.
--     It never persists that merge.
--   • Server (supabase/functions/_shared/modules.ts): `value?.[name]?.enabled === true`
--     — an absent row is `{}`, so EVERY module reads false. No default merge,
--     deliberately: the server has no business inventing an operator's config.
--
-- Neither side is wrong on its own. Together they mean a fresh install shows an
-- operator a working product while ~20 edge functions quietly no-op:
-- instance-health, event-dispatcher, automation-dispatcher, newsletter-send,
-- the MCP tool exposure in agent-execute, flowpilot-heartbeat. The sharpest
-- symptom is the skill registry: `sync_skills_from_code` is module-gated
-- server-side, reads `{}`, syncs only the `platform` pseudo-module, and a fresh
-- install lands on 14 skills instead of ~150 — with a green "synced" toast.
--
-- Measured on the local fresh replay (485 migrations): site_settings held two
-- rows, `cookie_consent_v2` and `visitor_intelligence_rules`. No `modules`.
--
-- THE FIX: one mechanism, two callers
-- -----------------------------------
-- `ensure_modules_settings(defaults jsonb)` is the single place that knows the
-- rule "fill what is missing, never overwrite what an operator chose". It is
-- re-assertable (CREATE OR REPLACE + additive body), not a one-shot INSERT —
-- the lesson from role_module_access_defaults, which a squash silently dropped
-- and nobody noticed for two months.
--
--   1. This migration calls it with a birth snapshot, so the SERVER is correct
--      before any browser has ever loaded. That matters: an instance can run
--      cron, webhooks and the public site for days before an admin logs in.
--   2. The admin shell calls it on every load with the LIVE
--      `defaultModulesSettings` (src/lib/module-bootstrap.ts → ensureModulesRow),
--      so a module added to the code after install still reaches the row. The
--      migration cannot do that — the ledger stops it from ever running again.
--
-- Caller 2 is why the snapshot below cannot drift into a lie: code stays the
-- source of truth, the snapshot is only the head start. A guardrail
-- (module-defaults-reach-the-server.guardrails.test.ts) holds caller 2 in place.
--
-- WHAT IT WILL NEVER DO
-- ---------------------
-- Touch a key that is already in the row. An operator who turned `blog` off
-- keeps it off, forever, including through a re-run of this file. Only absent
-- keys are added, and an absent key already read as `false` on the server — so
-- the only observable change is that the server starts agreeing with what the
-- admin UI has been showing all along.

CREATE OR REPLACE FUNCTION public.ensure_modules_settings(p_defaults jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $fn$
DECLARE
  v_existing   jsonb;
  v_normalised jsonb := '{}'::jsonb;
  v_added      text[] := ARRAY[]::text[];
  k            text;
BEGIN
  -- Internal guard from birth (the anon sweep's rule for every new SECURITY
  -- DEFINER function). The admin shell calls this as the logged-in admin, so
  -- REVOKE-from-authenticated is not available; the gate goes in the body.
  -- session_user is NOT rewritten by SECURITY DEFINER, so the third arm can
  -- only be reached from inside the database (migration / psql) — an API
  -- caller's session_user is always `authenticator`.
  IF NOT (
       auth.role() = 'service_role'
    OR has_role(auth.uid(), 'admin'::app_role)
    OR session_user IN ('postgres', 'supabase_admin')
  ) THEN
    RAISE EXCEPTION 'unauthorized: seeding module settings requires admin or service role';
  END IF;

  IF p_defaults IS NULL
     OR jsonb_typeof(p_defaults) <> 'object'
     OR p_defaults = '{}'::jsonb THEN
    RETURN jsonb_build_object('status', 'noop', 'reason', 'no defaults supplied');
  END IF;

  -- Store the MINIMAL shape: {id: {enabled: bool}}. Name/description/icon and
  -- every other structural field are owned by code (useModules.tsx overwrites
  -- them on read), so persisting them here would only manufacture stale copies.
  FOR k IN SELECT jsonb_object_keys(p_defaults) LOOP
    v_normalised := v_normalised || jsonb_build_object(
      k,
      jsonb_build_object('enabled', COALESCE((p_defaults -> k ->> 'enabled')::boolean, false))
    );
  END LOOP;

  SELECT value INTO v_existing FROM public.site_settings WHERE key = 'modules';

  -- No row at all, or a row whose value is not an object (JSON null / garbage).
  IF v_existing IS NULL OR jsonb_typeof(v_existing) <> 'object' THEN
    INSERT INTO public.site_settings (key, value)
    VALUES ('modules', v_normalised)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();

    RETURN jsonb_build_object(
      'status',  'created',
      'modules', (SELECT count(*) FROM jsonb_object_keys(v_normalised)),
      'enabled', (SELECT count(*) FROM jsonb_each(v_normalised) e WHERE (e.value ->> 'enabled')::boolean)
    );
  END IF;

  -- Row exists. Add only what is MISSING. An operator's choice always wins.
  FOR k IN SELECT jsonb_object_keys(v_normalised) LOOP
    IF NOT (v_existing ? k) THEN
      v_existing := v_existing || jsonb_build_object(k, v_normalised -> k);
      v_added := v_added || k;
    END IF;
  END LOOP;

  IF cardinality(v_added) = 0 THEN
    RETURN jsonb_build_object(
      'status',  'unchanged',
      'modules', (SELECT count(*) FROM jsonb_object_keys(v_existing))
    );
  END IF;

  UPDATE public.site_settings
     SET value = v_existing, updated_at = now()
   WHERE key = 'modules';

  RETURN jsonb_build_object(
    'status',  'filled',
    'added',   to_jsonb(v_added),
    'modules', (SELECT count(*) FROM jsonb_object_keys(v_existing))
  );
END;
$fn$;

ALTER FUNCTION public.ensure_modules_settings(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.ensure_modules_settings(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_modules_settings(jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_modules_settings(jsonb) TO authenticated, service_role;

COMMENT ON FUNCTION public.ensure_modules_settings(jsonb) IS
  'Seeds/tops up site_settings.modules from the code defaults. Adds missing module keys only — never overwrites an operator''s choice. Called once by migration 20260822190000 (birth snapshot) and on every admin load by ensureModulesRow() with the live defaultModulesSettings.';

-- ── Birth snapshot ─────────────────────────────────────────────────────────
-- A mirror of `defaultModulesSettings` (src/hooks/useModules.tsx) at
-- 2026-08-22: 67 modules, 7 enabled (analytics, pages, mediaLibrary,
-- siteMigration, templates, approvals, email). It only has to be right at
-- INSTALL time — caller 2 keeps the row current from the code afterwards.
DO $seed$
DECLARE
  v_result jsonb;
BEGIN
  IF to_regclass('public.site_settings') IS NULL THEN
    RAISE NOTICE 'site_settings missing — module row not seeded';
    RETURN;
  END IF;

  v_result := public.ensure_modules_settings($defaults${
  "analytics": {"enabled": true}, "bookings": {"enabled": false}, "pages": {"enabled": true}, "blog": {"enabled": false},
  "knowledgeBase": {"enabled": false}, "chat": {"enabled": false}, "liveSupport": {"enabled": false}, "newsletter": {"enabled": false},
  "forms": {"enabled": false}, "leads": {"enabled": false}, "deals": {"enabled": false}, "companies": {"enabled": false},
  "ecommerce": {"enabled": false}, "developer": {"enabled": false}, "globalElements": {"enabled": false}, "mediaLibrary": {"enabled": true},
  "webinars": {"enabled": false}, "salesIntelligence": {"enabled": false}, "consultants": {"enabled": false}, "browserControl": {"enabled": false},
  "federation": {"enabled": false}, "paidGrowth": {"enabled": false}, "companyInsights": {"enabled": false}, "visitorIntelligence": {"enabled": false},
  "flowpilot": {"enabled": false}, "tickets": {"enabled": false}, "siteMigration": {"enabled": true}, "composio": {"enabled": false},
  "templates": {"enabled": true}, "invoicing": {"enabled": false}, "accounting": {"enabled": false}, "expenses": {"enabled": false},
  "handbook": {"enabled": false}, "docs": {"enabled": false}, "timesheets": {"enabled": false}, "inventory": {"enabled": false},
  "purchasing": {"enabled": false}, "manufacturing": {"enabled": false}, "sla": {"enabled": false}, "contracts": {"enabled": false},
  "hr": {"enabled": false}, "documents": {"enabled": false}, "projects": {"enabled": false}, "calendar": {"enabled": false},
  "subscriptions": {"enabled": false}, "approvals": {"enabled": true}, "reconciliation": {"enabled": false}, "quotes": {"enabled": false},
  "email": {"enabled": true}, "recruitment": {"enabled": false}, "workspaceChat": {"enabled": false}, "customer360": {"enabled": false},
  "surveys": {"enabled": false}, "fieldService": {"enabled": false}, "maintenance": {"enabled": false}, "pos": {"enabled": false},
  "pricelists": {"enabled": false}, "returns": {"enabled": false}, "shipping": {"enabled": false}, "multiCurrency": {"enabled": false},
  "fixedAssets": {"enabled": false}, "payroll": {"enabled": false}, "wiki": {"enabled": false}, "river": {"enabled": false},
  "voice": {"enabled": false}, "webmeet": {"enabled": false}, "flowtable": {"enabled": false}
}$defaults$::jsonb);

  RAISE NOTICE 'site_settings.modules: %', v_result;
END $seed$;
