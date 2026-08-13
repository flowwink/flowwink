-- RLS reads the matrix: what you can see is what you can reach.
--
-- The role/module matrix (role_module_access) governed only the NAV — sidebar,
-- route guard, search palette. The DATA answered to a different, blunter
-- question: is_staff(), "do you have any role at all". So a salesperson whose
-- menu showed no Inventory could still read the stock tables over the API, and
-- granting a module in the matrix changed nothing at the data layer. Two
-- permission systems, unaware of each other (Magnus, 2026-08-13: "1:1 mellan
-- vad som syns och vad rollen har tillgång till").
--
-- From here the matrix is the single dial. can_access_module() asks it: admin
-- implicitly yes, otherwise any of the user's roles must have been granted the
-- module. Every is_staff() policy on a module-owned table is rewritten to name
-- its module — textually, preserving whatever else the policy expression said.
--
-- The mapping below is the reviewable artifact: 99 tables, each assigned to the
-- module whose toggle and matrix row govern it. knowledge_chunks is deliberately
-- absent — the Knowledge Index is a platform service with no module toggle
-- (one index, six sources), so "any staff" remains its correct read boundary.
--
-- What this deliberately does NOT touch:
--   • the ~485 has_role(admin) gates — admin actions stay admin's
--   • personal data (own profile, own time entries), public read, portal
--     policies — not module-owned, not module-gated
--   • service-role callers (FlowPilot, cron, edge functions) — RLS-exempt
--
-- Roles themselves are now pure data: their entire meaning is their matrix
-- rows. The eight departmental roles cost nothing to keep and nothing to add to.

CREATE OR REPLACE FUNCTION public.can_access_module(_user_id uuid, _module_id text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT public.has_role(_user_id, 'admin'::app_role)
      OR EXISTS (
           SELECT 1
             FROM public.user_roles ur
             JOIN public.role_module_access rma ON rma.role = ur.role
            WHERE ur.user_id = _user_id
              AND rma.module_id = _module_id
         );
$$;

GRANT EXECUTE ON FUNCTION public.can_access_module(uuid, text) TO authenticated, anon, service_role;

DO $$
DECLARE
  MAP CONSTANT text[][] := ARRAY[
    ARRAY['approval_chains', 'approvals'],
    ARRAY['approval_delegations', 'approvals'],
    ARRAY['approval_group_members', 'approvals'],
    ARRAY['approval_groups', 'approvals'],
    ARRAY['approval_steps', 'approvals'],
    ARRAY['back_in_stock_requests', 'ecommerce'],
    ARRAY['bookings', 'bookings'],
    ARRAY['calendar_events', 'calendar'],
    ARRAY['companies', 'companies'],
    ARRAY['consultant_assignments', 'consultants'],
    ARRAY['consultant_checkin_log', 'consultants'],
    ARRAY['consultant_profiles', 'consultants'],
    ARRAY['consultant_skill_rates', 'consultants'],
    ARRAY['contact_consents', 'leads'],
    ARRAY['content_proposals', 'paidGrowth'],
    ARRAY['contract_documents', 'contracts'],
    ARRAY['contract_versions', 'contracts'],
    ARRAY['cowork_messages', 'workspaceChat'],
    ARRAY['crm_tasks', 'leads'],
    ARRAY['deal_activities', 'deals'],
    ARRAY['deal_history', 'deals'],
    ARRAY['deals', 'deals'],
    ARRAY['discount_codes', 'ecommerce'],
    ARRAY['document_share_links', 'documents'],
    ARRAY['document_signature_requests', 'documents'],
    ARRAY['document_versions', 'documents'],
    ARRAY['equipment', 'maintenance'],
    ARRAY['form_submissions', 'forms'],
    ARRAY['gift_cards', 'pos'],
    ARRAY['goods_receipt_lines', 'purchasing'],
    ARRAY['goods_receipts', 'purchasing'],
    ARRAY['inventory_count_lines', 'inventory'],
    ARRAY['inventory_counts', 'inventory'],
    ARRAY['kb_article_revisions', 'knowledgeBase'],
    ARRAY['kb_articles', 'knowledgeBase'],
    ARRAY['landed_costs', 'inventory'],
    ARRAY['lead_activities', 'leads'],
    ARRAY['lead_email_blast_recipients', 'leads'],
    ARRAY['lead_email_blasts', 'leads'],
    ARRAY['leads', 'leads'],
    ARRAY['loyalty_accounts', 'pos'],
    ARRAY['loyalty_transactions', 'pos'],
    ARRAY['maintenance_requests', 'maintenance'],
    ARRAY['maintenance_schedules', 'maintenance'],
    ARRAY['mo_work_orders', 'manufacturing'],
    ARRAY['newsletter_email_opens', 'newsletter'],
    ARRAY['newsletter_link_clicks', 'newsletter'],
    ARRAY['newsletter_subscribers', 'newsletter'],
    ARRAY['newsletters', 'newsletter'],
    ARRAY['outbound_communications', 'email'],
    ARRAY['pipeline_stages', 'deals'],
    ARRAY['pos_payments', 'pos'],
    ARRAY['pos_sale_lines', 'pos'],
    ARRAY['pos_sales', 'pos'],
    ARRAY['pos_sessions', 'pos'],
    ARRAY['pos_tables', 'pos'],
    ARRAY['products', 'ecommerce'],
    ARRAY['project_milestones', 'projects'],
    ARRAY['project_task_dependencies', 'projects'],
    ARRAY['project_tasks', 'projects'],
    ARRAY['project_templates', 'projects'],
    ARRAY['purchase_order_lines', 'purchasing'],
    ARRAY['purchase_order_revisions', 'purchasing'],
    ARRAY['purchase_orders', 'purchasing'],
    ARRAY['quote_attachments', 'quotes'],
    ARRAY['quote_items', 'quotes'],
    ARRAY['quote_revisions', 'quotes'],
    ARRAY['quote_signatures', 'quotes'],
    ARRAY['quote_templates', 'quotes'],
    ARRAY['quote_versions', 'quotes'],
    ARRAY['quotes', 'quotes'],
    ARRAY['recurring_quote_templates', 'quotes'],
    ARRAY['rfq_bids', 'purchasing'],
    ARRAY['rfq_lines', 'purchasing'],
    ARRAY['rfqs', 'purchasing'],
    ARRAY['routing_operations', 'manufacturing'],
    ARRAY['service_credits', 'sla'],
    ARRAY['service_packages', 'fieldService'],
    ARRAY['shipping_pickups', 'shipping'],
    ARRAY['sla_clock_pauses', 'sla'],
    ARRAY['sla_tier_assignments', 'sla'],
    ARRAY['sla_tiers', 'sla'],
    ARRAY['stock_valuation_layers', 'inventory'],
    ARRAY['subscription_events', 'subscriptions'],
    ARRAY['subscription_plans', 'subscriptions'],
    ARRAY['subscriptions', 'subscriptions'],
    ARRAY['support_escalations', 'tickets'],
    ARRAY['ticket_comments', 'tickets'],
    ARRAY['ticket_escalation_rules', 'tickets'],
    ARRAY['ticket_team_members', 'tickets'],
    ARRAY['ticket_teams', 'tickets'],
    ARRAY['ticket_time_entries', 'tickets'],
    ARRAY['tickets', 'tickets'],
    ARRAY['vendor_credit_memos', 'purchasing'],
    ARRAY['vendor_invoice_disputes', 'purchasing'],
    ARRAY['vendors', 'purchasing'],
    ARRAY['webinars', 'webinars'],
    ARRAY['wiki_pages', 'wiki'],
    ARRAY['work_centers', 'manufacturing']
  ];
  pair text[];
  pol record;
  new_qual text;
  new_check text;
  n_rewritten int := 0;
  n_skipped int := 0;
BEGIN
  FOREACH pair SLICE 1 IN ARRAY MAP LOOP
    IF to_regclass('public.' || pair[1]) IS NULL THEN
      CONTINUE; -- instance predates the table; nothing to rewrite
    END IF;
    FOR pol IN
      SELECT policyname, tablename, cmd, qual, with_check
        FROM pg_policies
       WHERE schemaname = 'public'
         AND tablename = pair[1]
         AND (qual LIKE '%is_staff(auth.uid())%' OR with_check LIKE '%is_staff(auth.uid())%')
    LOOP
      new_qual  := replace(pol.qual,       'is_staff(auth.uid())', format('can_access_module(auth.uid(), %L)', pair[2]));
      new_check := replace(pol.with_check, 'is_staff(auth.uid())', format('can_access_module(auth.uid(), %L)', pair[2]));
      IF pol.qual IS NOT NULL AND pol.with_check IS NOT NULL THEN
        EXECUTE format('ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)', pol.policyname, pol.tablename, new_qual, new_check);
      ELSIF pol.qual IS NOT NULL THEN
        EXECUTE format('ALTER POLICY %I ON public.%I USING (%s)', pol.policyname, pol.tablename, new_qual);
      ELSE
        EXECUTE format('ALTER POLICY %I ON public.%I WITH CHECK (%s)', pol.policyname, pol.tablename, new_check);
      END IF;
      n_rewritten := n_rewritten + 1;
    END LOOP;
  END LOOP;

  SELECT count(*) INTO n_skipped
    FROM pg_policies
   WHERE schemaname = 'public'
     AND (qual LIKE '%is_staff%' OR with_check LIKE '%is_staff%');

  RAISE NOTICE 'matrix-RLS: % policies rewritten to can_access_module; % is_staff policies remain (deliberate exceptions)', n_rewritten, n_skipped;
END $$;
