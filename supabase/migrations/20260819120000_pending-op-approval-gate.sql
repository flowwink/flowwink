-- Svante-fynd 2026-08-19: FlowWorks Approve-knapp gick via skill-lagret där
-- approve_pending_operation ägs av approvals-modulen → 403 för sales/marketing
-- trots accept. Utredningen blottade det motsatta hålet: DB-funktionerna
-- saknade grind helt (SECURITY DEFINER utan rollkoll) — direkta RPC-anrop
-- kunde godkänna VEMS SOM HELST stagade operation.
--
-- Rätt regel: självbekräftelse är skaparens rätt (FlowWorks staged-flöde är
-- en bekräftelsegest — själva skrivningen grindas ändå av målskillens modul
-- vid återinvokeringen). Andras operationer kräver approvals-modulen/admin.

CREATE OR REPLACE FUNCTION public.approve_pending_operation(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_op record;
BEGIN
  SELECT * INTO v_op FROM public.pending_operations WHERE id = p_id;
  IF v_op IS NULL THEN RETURN jsonb_build_object('error', 'pending operation not found'); END IF;
  IF NOT (auth.role() = 'service_role'
          OR public.has_role(auth.uid(), 'admin')
          OR public.can_access_module(auth.uid(), 'approvals')
          OR (v_op.created_by_user_id IS NOT NULL AND v_op.created_by_user_id = auth.uid())) THEN
    RETURN jsonb_build_object('error', 'Not allowed: only the operation''s creator, an approvals-module role or an admin may approve it');
  END IF;
  IF v_op.status <> 'pending' THEN RETURN jsonb_build_object('error', 'operation already ' || v_op.status); END IF;
  UPDATE public.pending_operations SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now() WHERE id = p_id;
  RETURN jsonb_build_object('approved', true, 'id', p_id, 'skill_name', v_op.skill_name,
    'next', 'Re-invoke the skill with the same args plus _approved_operation_id="' || p_id || '" to execute.');
END; $function$;

CREATE OR REPLACE FUNCTION public.reject_pending_operation(p_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_op record;
BEGIN
  SELECT * INTO v_op FROM public.pending_operations WHERE id = p_id;
  IF v_op IS NULL THEN RETURN jsonb_build_object('error', 'operation not pending or not found'); END IF;
  IF NOT (auth.role() = 'service_role'
          OR public.has_role(auth.uid(), 'admin')
          OR public.can_access_module(auth.uid(), 'approvals')
          OR (v_op.created_by_user_id IS NOT NULL AND v_op.created_by_user_id = auth.uid())) THEN
    RETURN jsonb_build_object('error', 'Not allowed: only the operation''s creator, an approvals-module role or an admin may reject it');
  END IF;
  UPDATE public.pending_operations SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), rejection_reason = p_reason
    WHERE id = p_id AND status = 'pending';
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'operation already ' || v_op.status); END IF;
  RETURN jsonb_build_object('rejected', true, 'id', p_id, 'reason', p_reason);
END; $function$;
