-- Close the inbound email loop: replies land on the CUSTOMER, not in a mailbox.
--
-- The shared-inbox machinery already existed and was never connected:
--   outbound_communications carries direction, thread_id, message_id_header,
--     in_reply_to, sender and related_entity_type/id — i.e. BOTH directions.
--   trg_touch_email_thread (BEFORE INSERT) normalises a thread_key from
--     thread_id, or from the subject with Re:/Fwd: stripped, and upserts
--     email_threads carrying related_entity_*.
-- But nothing ever wrote an inbound row, so the fleet had 1 thread and 1
-- outbound message. The pipe was built; the tap was never opened.
--
-- This migration adds only what ingestion needs: idempotency. The handler is
-- code (_shared/handlers/ingest-inbound-email.ts).
--
-- WHY THIS SHAPE, not per-user mailboxes: the goal is that a customer's reply
-- is visible ON THE CUSTOMER. Individual mailboxes actively defeat that — a
-- reply to a salesperson's own Gmail is invisible to the CRM and to FlowPilot.
-- One company mailbox, threads bound to entities, and per-user identity as
-- presentation (profiles.email_from_name) is the shape that keeps the
-- conversation in the system.

-- Gmail's message id is globally unique and stable, so it is the natural
-- dedup key. Partial, because outbound rows written before this loop existed
-- (and any transport that does not report one) carry NULL.
CREATE UNIQUE INDEX IF NOT EXISTS outbound_communications_message_id_uniq
  ON public.outbound_communications (message_id_header)
  WHERE message_id_header IS NOT NULL;

COMMENT ON INDEX public.outbound_communications_message_id_uniq IS
  'Idempotency for inbound ingestion: re-scanning the same mailbox must not '
  'duplicate messages. Partial because pre-loop and non-reporting transports '
  'leave message_id_header NULL.';
