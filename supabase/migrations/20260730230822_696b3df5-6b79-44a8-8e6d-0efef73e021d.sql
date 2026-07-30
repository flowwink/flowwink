UPDATE public.agent_automations
SET skill_arguments = COALESCE(skill_arguments, '{}'::jsonb) || jsonb_build_object(
      'classification', '{{event.payload.classification}}',
      'should_create_ticket', '{{event.payload.should_create_ticket}}',
      'route_mode', '{{event.payload.route_mode}}'
    )
WHERE name = 'inbound_email_to_ticket';