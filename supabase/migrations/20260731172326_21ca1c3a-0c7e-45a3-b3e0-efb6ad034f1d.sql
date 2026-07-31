CREATE OR REPLACE FUNCTION public.can_view_ticket(_ticket_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tickets t
    LEFT JOIN public.profiles p ON p.id = auth.uid()
    WHERE t.id = _ticket_id
      AND auth.uid() IS NOT NULL
      AND (
        t.created_by = auth.uid()
        OR (p.email IS NOT NULL AND lower(t.contact_email) = lower(p.email))
        OR (
          t.company_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM public.company_contacts cc
            WHERE cc.auth_user_id = auth.uid()
              AND cc.company_id = t.company_id
              AND cc.status = 'active'
          )
        )
      )
  )
$$;

GRANT EXECUTE ON FUNCTION public.can_view_ticket(uuid) TO authenticated;
GRANT SELECT ON public.tickets TO authenticated;
GRANT SELECT, INSERT ON public.ticket_comments TO authenticated;

DROP POLICY IF EXISTS "Customers can view own tickets" ON public.tickets;
CREATE POLICY "Customers can view own tickets"
ON public.tickets
FOR SELECT
TO authenticated
USING (public.can_view_ticket(id));

DROP POLICY IF EXISTS "Customers can view public ticket comments" ON public.ticket_comments;
CREATE POLICY "Customers can view public ticket comments"
ON public.ticket_comments
FOR SELECT
TO authenticated
USING (is_internal = false AND public.can_view_ticket(ticket_id));

DROP POLICY IF EXISTS "Customers can reply on own tickets" ON public.ticket_comments;
CREATE POLICY "Customers can reply on own tickets"
ON public.ticket_comments
FOR INSERT
TO authenticated
WITH CHECK (is_internal = false AND public.can_view_ticket(ticket_id));