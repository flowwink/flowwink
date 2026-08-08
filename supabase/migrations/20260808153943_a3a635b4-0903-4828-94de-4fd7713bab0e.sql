CREATE OR REPLACE FUNCTION public.schedule_voice_callback(
  p_call_id uuid,
  p_scheduled_at timestamptz,
  p_agent_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _call record;
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role) OR auth.uid() IS NULL) THEN
    RAISE EXCEPTION 'Only admins or system can schedule a callback';
  END IF;

  SELECT * INTO _call FROM public.voice_calls WHERE id = p_call_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voice call % not found', p_call_id;
  END IF;

  IF _call.callback_status = 'completed' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'call_id', p_call_id,
      'callback_status', 'completed',
      'note', 'Callback already completed — nothing to schedule.'
    );
  END IF;

  UPDATE public.voice_calls
     SET callback_status = 'scheduled',
         callback_scheduled_at = p_scheduled_at,
         agent_id = COALESCE(p_agent_id, agent_id),
         updated_at = now()
   WHERE id = p_call_id;

  RETURN jsonb_build_object(
    'ok', true,
    'call_id', p_call_id,
    'callback_status', 'scheduled',
    'callback_scheduled_at', p_scheduled_at,
    'agent_id', COALESCE(p_agent_id, _call.agent_id)
  );
END $function$;

CREATE OR REPLACE FUNCTION public.mark_voice_callback_done(
  p_call_id uuid,
  p_outcome text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _call record;
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role) OR auth.uid() IS NULL) THEN
    RAISE EXCEPTION 'Only admins or system can complete a callback';
  END IF;

  SELECT * INTO _call FROM public.voice_calls WHERE id = p_call_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Voice call % not found', p_call_id;
  END IF;

  IF _call.callback_status = 'completed' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'call_id', p_call_id,
      'callback_status', 'completed',
      'callback_completed_at', _call.callback_completed_at
    );
  END IF;

  IF _call.callback_status NOT IN ('scheduled', 'pending') THEN
    RAISE EXCEPTION 'Callback for call % is %, expected scheduled or pending', p_call_id, _call.callback_status;
  END IF;

  UPDATE public.voice_calls
     SET callback_status = 'completed',
         callback_completed_at = now(),
         metadata = CASE
           WHEN p_outcome IS NULL THEN metadata
           ELSE COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('callback_outcome', p_outcome)
         END,
         updated_at = now()
   WHERE id = p_call_id;

  RETURN jsonb_build_object(
    'ok', true,
    'call_id', p_call_id,
    'callback_status', 'completed',
    'callback_completed_at', now(),
    'callback_outcome', p_outcome
  );
END $function$;

CREATE OR REPLACE FUNCTION public.support_assign_conversation(
  p_conversation_id uuid,
  p_agent_id uuid DEFAULT NULL,
  p_status text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _conv record;
BEGIN
  IF NOT (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'::app_role) OR auth.uid() IS NULL) THEN
    RAISE EXCEPTION 'Only admins or system can assign a support conversation';
  END IF;

  IF p_agent_id IS NULL AND p_status IS NULL THEN
    RAISE EXCEPTION 'Provide p_agent_id, p_status, or both';
  END IF;

  SELECT * INTO _conv FROM public.chat_conversations WHERE id = p_conversation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation % not found', p_conversation_id;
  END IF;

  UPDATE public.chat_conversations
     SET assigned_agent_id = COALESCE(p_agent_id, assigned_agent_id),
         conversation_status = COALESCE(p_status, conversation_status),
         updated_at = now()
   WHERE id = p_conversation_id;

  RETURN jsonb_build_object(
    'ok', true,
    'conversation_id', p_conversation_id,
    'assigned_agent_id', COALESCE(p_agent_id, _conv.assigned_agent_id),
    'conversation_status', COALESCE(p_status, _conv.conversation_status)
  );
END $function$;

GRANT EXECUTE ON FUNCTION public.schedule_voice_callback(uuid, timestamptz, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_voice_callback_done(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.support_assign_conversation(uuid, uuid, text) TO authenticated, service_role;

-- ===== KB article visibility =====
ALTER TABLE public.kb_articles
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'kb_articles_visibility_check'
  ) THEN
    ALTER TABLE public.kb_articles
      ADD CONSTRAINT kb_articles_visibility_check
      CHECK (visibility IN ('public', 'internal'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS kb_articles_visibility_published_idx
  ON public.kb_articles (visibility, is_published);

CREATE OR REPLACE FUNCTION public.is_staff(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role <> 'customer'
  );
$$;

DROP POLICY IF EXISTS "Public can view published articles" ON public.kb_articles;
DROP POLICY IF EXISTS "Public can view published public articles" ON public.kb_articles;
CREATE POLICY "Public can view published public articles"
  ON public.kb_articles FOR SELECT
  USING (is_published = true AND visibility = 'public');

DROP POLICY IF EXISTS "Authenticated can view all articles" ON public.kb_articles;
DROP POLICY IF EXISTS "Staff view all articles, others the public ones" ON public.kb_articles;
CREATE POLICY "Staff view all articles, others the public ones"
  ON public.kb_articles FOR SELECT
  TO authenticated
  USING (
    public.is_staff(auth.uid())
    OR (is_published = true AND visibility = 'public')
  );