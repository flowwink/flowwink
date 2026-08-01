CREATE OR REPLACE FUNCTION public.assign_voucher_number()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_series text; v_year int; v_next bigint;
BEGIN
  IF NEW.voucher_number IS NOT NULL AND NEW.voucher_series IS NOT NULL THEN RETURN NEW; END IF;
  v_year := EXTRACT(YEAR FROM NEW.entry_date)::int;
  NEW.voucher_year := v_year;
  IF NEW.voucher_series IS NULL THEN
    SELECT COALESCE(j.sequence_prefix, j.code, 'GEN') INTO v_series
      FROM public.journals j WHERE j.id = NEW.journal_id;
    NEW.voucher_series := COALESCE(v_series, 'GEN');
  END IF;
  IF NEW.voucher_number IS NULL THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('voucher:' || NEW.voucher_series || ':' || v_year::text, 0)
    );
    SELECT COALESCE(MAX(voucher_number), 0) + 1 INTO v_next
      FROM public.journal_entries
      WHERE voucher_series = NEW.voucher_series AND voucher_year = v_year;
    NEW.voucher_number := v_next;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_assign_voucher_number ON public.journal_entries;
CREATE TRIGGER trg_assign_voucher_number BEFORE INSERT ON public.journal_entries
  FOR EACH ROW EXECUTE FUNCTION public.assign_voucher_number();

UPDATE public.webinar_registrations r
SET reminder_confirm_sent_at = now()
WHERE r.reminder_confirm_sent_at IS NULL
  AND r.registered_at < now() - interval '24 hours';

UPDATE public.webinar_registrations r
SET reminder_t24_sent_at = COALESCE(r.reminder_t24_sent_at, now()),
    reminder_t1_sent_at = COALESCE(r.reminder_t1_sent_at, now())
WHERE (r.reminder_t24_sent_at IS NULL OR r.reminder_t1_sent_at IS NULL)
  AND EXISTS (SELECT 1 FROM public.webinars w WHERE w.id = r.webinar_id AND w.date < now());

UPDATE public.webinar_registrations r
SET reminder_post_sent_at = now()
WHERE r.reminder_post_sent_at IS NULL
  AND EXISTS (SELECT 1 FROM public.webinars w WHERE w.id = r.webinar_id AND w.date < now() - interval '7 days');