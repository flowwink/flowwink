GRANT UPDATE ON public.outbound_communications TO authenticated;

DROP POLICY IF EXISTS "admins link outbound communications" ON public.outbound_communications;
CREATE POLICY "admins link outbound communications"
ON public.outbound_communications
FOR UPDATE
TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));