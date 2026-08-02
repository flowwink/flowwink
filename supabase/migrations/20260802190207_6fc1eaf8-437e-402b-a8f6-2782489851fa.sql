ALTER TABLE "public"."mo_work_orders"
  ADD COLUMN IF NOT EXISTS "actual_labor_cost_cents" integer;

CREATE OR REPLACE FUNCTION "public"."progress_work_order"(
  "p_work_order_id" "uuid",
  "p_action" "text",
  "p_actual_minutes" numeric DEFAULT NULL
)
RETURNS "jsonb" LANGUAGE "plpgsql" SECURITY DEFINER SET "search_path" TO 'public' AS $$
DECLARE
  v_writer boolean := (auth.role() = 'service_role' OR has_role(auth.uid(), 'admin'));
  v_wo RECORD;
  v_rate int := 0;
  v_minutes numeric;
  v_cost int;
BEGIN
  IF NOT v_writer THEN RAISE EXCEPTION 'Only admins can progress work orders'; END IF;

  SELECT * INTO v_wo FROM mo_work_orders WHERE id = p_work_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Work order % not found', p_work_order_id; END IF;

  SELECT COALESCE(wc.cost_per_hour_cents, 0) INTO v_rate
    FROM work_centers wc WHERE wc.id = v_wo.work_center_id;
  v_rate := COALESCE(v_rate, 0);

  IF p_action = 'start' THEN
    IF v_wo.status = 'done' THEN RAISE EXCEPTION 'Work order already done'; END IF;
    UPDATE mo_work_orders
      SET status = 'in_progress',
          started_at = COALESCE(started_at, now())
      WHERE id = p_work_order_id;

  ELSIF p_action = 'pause' THEN
    IF v_wo.status <> 'in_progress' THEN RAISE EXCEPTION 'Only an in-progress work order can be paused'; END IF;
    v_minutes := COALESCE(
      p_actual_minutes,
      COALESCE(v_wo.actual_minutes, 0) + EXTRACT(EPOCH FROM (now() - COALESCE(v_wo.started_at, now()))) / 60.0
    );
    UPDATE mo_work_orders
      SET status = 'pending',
          actual_minutes = ROUND(v_minutes, 2),
          actual_labor_cost_cents = ROUND(v_minutes / 60.0 * v_rate)::int
      WHERE id = p_work_order_id;

  ELSIF p_action = 'done' THEN
    v_minutes := COALESCE(
      p_actual_minutes,
      v_wo.actual_minutes,
      CASE WHEN v_wo.started_at IS NOT NULL
        THEN EXTRACT(EPOCH FROM (now() - v_wo.started_at)) / 60.0
        ELSE v_wo.planned_minutes END
    );
    v_cost := ROUND(v_minutes / 60.0 * v_rate)::int;
    UPDATE mo_work_orders
      SET status = 'done',
          started_at = COALESCE(started_at, now()),
          completed_at = now(),
          actual_minutes = ROUND(v_minutes, 2),
          actual_labor_cost_cents = v_cost
      WHERE id = p_work_order_id;

  ELSIF p_action = 'cancel' THEN
    UPDATE mo_work_orders SET status = 'cancelled' WHERE id = p_work_order_id;

  ELSE
    RAISE EXCEPTION 'Unknown action: %. Use start|pause|done|cancel', p_action;
  END IF;

  SELECT * INTO v_wo FROM mo_work_orders WHERE id = p_work_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'work_order_id', p_work_order_id,
    'mo_id', v_wo.mo_id,
    'status', v_wo.status,
    'actual_minutes', v_wo.actual_minutes,
    'actual_labor_cost_cents', v_wo.actual_labor_cost_cents,
    'variance_minutes', COALESCE(v_wo.actual_minutes, 0) - v_wo.planned_minutes,
    'mo_open_work_orders', (
      SELECT COUNT(*) FROM mo_work_orders
      WHERE mo_id = v_wo.mo_id AND status NOT IN ('done', 'cancelled')
    )
  );
END; $$;

GRANT ALL ON FUNCTION "public"."progress_work_order"("uuid", "text", numeric)
  TO "anon", "authenticated", "service_role";