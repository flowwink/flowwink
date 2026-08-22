-- Leveransen raderade betalningen: `orders.status` bar två axlar (#249).
--
-- `ship_picking` avslutade med
--   UPDATE public.orders SET status = 'shipped' WHERE id = v_po.order_id;
-- Ordern gick in som status='paid', fulfillment_status='unfulfilled'. Efter
-- leverans stod status='shipped' — och att den var BETALD gick inte längre att
-- läsa någonstans. Fältet bar två axlar, och den som skrev sist vann.
--
-- INCIDENTKLASS: två axlar i ett fält. Ett tillstånd som består av två
-- oberoende fakta ("har vi fått pengarna" och "var är godset") kan inte
-- representeras i en kolumn — varje skrivning på den ena axeln raderar den
-- andra. Klassen är förrädisk för att den ser rätt ut i vyn: badgen visar
-- "Shipped" och ingen saknar "Paid" förrän någon frågar vad vi fått betalt för.
--
-- REGEL: en kolumn per axel. `orders` bar redan `fulfillment_status` (default
-- 'unfulfilled') plus picked_at/packed_at/shipped_at/delivered_at. Leveransen
-- hörde hemma där hela tiden; `status` är pengar och livscykel.
--
-- Samma bugg rättades i agent-lagret 2026-08-20 (manage_orders skrev varje
-- värde till orders.status, så `deliver` på en betald order skrev över 'paid').
-- Spärren som föll ut av det — order-to-cash-links.guardrails, "a fulfillment
-- update writes fulfillment_status and never orders.status" — täckte bara
-- agent-execute. SQL-vägen och admin-UI:t bar kvar överskrivningen. Den här
-- migrationen stänger SQL-vägen; UI-vägen stängs i samma ändring
-- (FulfillmentActions.tsx).
--
-- KONSEKVENSANALYS (vad läser vilken axel — svepet gjordes innan skrivningen togs bort):
--   • INGEN fråga filtrerar på orders.status = 'shipped'. Inte i src/, inte i
--     edge-funktionerna. Värdet skrevs och lästes aldrig som filter.
--   • Intäkt räknas på `paid|completed` (admin OrdersPage, manage_orders stats)
--     respektive enbart `completed` (flowpilot-briefing). En order som skeppats
--     försvann alltså UR intäkten så fort den skeppades — fixen lagar
--     rapporteringen, den bryter den inte.
--   • Admin OrdersPage visar redan TVÅ badgar (STATUS_* och FULFILLMENT_*), så
--     "Shipped" står kvar i vyn — nu på rätt axel.
--   • OrderTrackingPage (publik) har redan en egen tidslinje på
--     fulfillment_status via lookup_order_tracking.
--   • CheckoutSuccessPage saknar 'shipped' i sin statusConfig helt — den
--     skrivningen var ett latent undefined-uppslag där.
--   • Kundportalens orderlista (account/OrdersPage) renderade RÅ orders.status
--     och var därmed den enda ytan som visade leverans genom betalningsaxeln.
--     Den pekas om till fulfillment_status i samma ändring.
--
-- Kroppen nedan är dumpad live (pg_get_functiondef) och återlagd oförändrad så
-- när som på den sista UPDATE-satsen mot `orders`. Tre saker om den satsen:
--   1. `status` rörs inte alls.
--   2. `shipped_at` sätts INTE explicit — och det är avsiktligt. Triggern
--      validate_fulfillment_status (BEFORE UPDATE) stämplar shipped_at OCH
--      fyller i picked_at/packed_at retroaktivt, men bara i grenen
--      `... AND NEW.shipped_at IS NULL`. Sätter vi shipped_at själva hoppar
--      hela grenen och tidslinjen i FulfillmentStepper blir hålig.
--   3. WHERE-villkoret `fulfillment_status IN ('unfulfilled','picked','packed')`
--      gör satsen omkörbar och hindrar att en redan levererad order backas till
--      'shipped'. En andra parcel på samma order är ett `shipments`-ärende, inte
--      en omskrivning av orderhuvudet.
--
-- CREATE OR REPLACE FUNCTION är omkörbart av konstruktion.

CREATE OR REPLACE FUNCTION public.ship_picking(p_picking_order_id uuid, p_tracking_number text DEFAULT NULL::text, p_carrier text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_po RECORD; v_line RECORD;
  v_consumed INT := 0; v_reserved_lines INT := 0; v_failed jsonb := '[]'::jsonb;
  v_carrier_id uuid; v_carrier_code text; v_active_count int;
  v_move_stock boolean;
BEGIN
  IF NOT (auth.role() = 'service_role' OR can_access_module(auth.uid(),'inventory')) THEN
    RAISE EXCEPTION 'Insufficient permissions';
  END IF;

  SELECT * INTO v_po FROM public.picking_orders WHERE id = p_picking_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Picking order % not found', p_picking_order_id; END IF;
  IF v_po.status = 'shipped' THEN RETURN jsonb_build_object('success', true, 'already_shipped', true); END IF;
  IF v_po.status = 'cancelled' THEN RAISE EXCEPTION 'Cannot ship cancelled picking_order'; END IF;

  -- 4b85909f: resolve p_carrier against the carriers table (id, code or name,
  -- case-insensitive). Unknown values are rejected while active carriers
  -- exist; when none are configured yet, free text passes (fail forward).
  IF p_carrier IS NOT NULL AND btrim(p_carrier) <> '' THEN
    SELECT c.id, c.code INTO v_carrier_id, v_carrier_code
      FROM public.carriers c
     WHERE c.is_active
       AND (c.id::text = btrim(p_carrier)
            OR lower(c.code) = lower(btrim(p_carrier))
            OR lower(c.name) = lower(btrim(p_carrier)))
     LIMIT 1;
    IF v_carrier_id IS NULL THEN
      SELECT count(*) INTO v_active_count FROM public.carriers WHERE is_active;
      IF v_active_count > 0 THEN
        RAISE EXCEPTION 'Unknown carrier "%" — pass an active carrier id, code or name. Active carriers: %',
          p_carrier, (SELECT string_agg(code, ', ' ORDER BY code) FROM public.carriers WHERE is_active);
      END IF;
    END IF;
  END IF;

  -- Order entry already took these goods off the shelf (trg_order_item_stock_decrement).
  -- A picking with no order behind it — an agent's own reservation — has not.
  v_move_stock := (v_po.order_id IS NULL);

  FOR v_line IN
    SELECT * FROM public.picking_lines
     WHERE picking_order_id = p_picking_order_id AND status = 'picked'
  LOOP
    IF v_line.reservation_id IS NOT NULL THEN
      v_reserved_lines := v_reserved_lines + 1;
      BEGIN
        -- Two arguments, not three: the second is a LOCATION CODE. Passing
        -- qty_picked here is what made this call unresolvable.
        PERFORM public.consume_reservation(v_line.reservation_id, 'WH/CUSTOMERS', v_move_stock);
        v_consumed := v_consumed + 1;
      EXCEPTION
        WHEN undefined_function OR undefined_column OR undefined_table THEN
          RAISE;
        WHEN OTHERS THEN
          v_failed := v_failed || jsonb_build_object('line_id', v_line.id, 'error', left(SQLERRM, 200));
          INSERT INTO public.audit_logs (action, entity_type, entity_id, user_id, metadata)
          VALUES ('picking.consume_failed', 'picking_line', v_line.id, auth.uid(),
                  jsonb_build_object('error', SQLERRM));
      END;
    END IF;
  END LOOP;

  UPDATE public.picking_orders
     SET status = 'shipped', shipped_at = now(),
         tracking_number = COALESCE(p_tracking_number, tracking_number),
         carrier = COALESCE(v_carrier_code, p_carrier, carrier),
         carrier_id = COALESCE(v_carrier_id, carrier_id)
   WHERE id = p_picking_order_id;

  -- #249: the shipment moves the FULFILLMENT axis. `status` carries money and
  -- lifecycle (pending/paid/completed/cancelled/refunded/failed) and is left
  -- exactly as the payment flow wrote it — a paid order stays readable as paid
  -- after it ships. shipped_at is deliberately NOT set here: the BEFORE UPDATE
  -- trigger validate_fulfillment_status stamps it and backfills
  -- picked_at/packed_at, but only while shipped_at is still NULL.
  IF v_po.order_id IS NOT NULL THEN
    UPDATE public.orders
       SET fulfillment_status = 'shipped',
           tracking_number = COALESCE(p_tracking_number, tracking_number),
           updated_at = now()
     WHERE id = v_po.order_id
       AND fulfillment_status IN ('unfulfilled', 'picked', 'packed');
  END IF;

  BEGIN
    PERFORM public.emit_platform_event('picking.shipped', jsonb_build_object(
      'picking_order_id', p_picking_order_id, 'order_id', v_po.order_id,
      'tracking_number', p_tracking_number, 'carrier_id', v_carrier_id,
      'consumed_lines', v_consumed), 'pick_pack');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  INSERT INTO public.audit_logs (action, entity_type, entity_id, user_id, metadata)
  VALUES ('picking.shipped', 'picking_order', p_picking_order_id, auth.uid(),
          jsonb_build_object('order_id', v_po.order_id, 'tracking_number', p_tracking_number,
                             'carrier_id', v_carrier_id, 'consumed', v_consumed));

  -- reserved_lines vs consumed is the whole point: a caller that reads only
  -- `success` cannot tell a shipment from a status change. Now it can.
  RETURN jsonb_build_object(
    'success', true,
    'picking_order_id', p_picking_order_id,
    'reserved_lines', v_reserved_lines,
    'consumed_lines', v_consumed,
    'stock_moved', v_move_stock,
    'failed_lines', v_failed,
    'carrier_id', v_carrier_id,
    'carrier_code', v_carrier_code
  );
END; $function$;

-- ── Efterbörden: raderna som redan förlorat sin betalningsstatus ────────────
--
-- Leveransaxeln går att återskapa: står `status = 'shipped'` så HAR någon
-- (ship_picking, eller en admin i statusrullgardinen) sagt att godset gått. Det
-- flyttas till rätt kolumn, och validate_fulfillment_status stämplar då
-- shipped_at plus de picked_at/packed_at som aldrig sattes.
--
-- Betalningsaxeln återskapas INTE här, och det är ett beslut, inte en lucka:
--   • Faktumet är förstört. Att härleda 'paid' ur stripe_payment_intent eller
--     en betald faktura är en GISSNING — en order kan ha skeppats mot faktura,
--     mot förskott, eller aldrig ha betalats alls.
--   • En skrivning av status='paid' är inte heller stum: tg_emit_order_events
--     och tr_orders_emit_paid emitterar `order.paid` på övergången, och den
--     signalen går ut på automationsrälsen. En migration som "lagar" statistik
--     genom att skicka orderbekräftelser månader i efterhand är en värre bugg
--     än den den lagar.
-- Raderna lämnas därför kvar på status='shipped' (fortsatt renderbart —
-- STATUS_LABELS behåller etiketten som legacy) för en människa att avgöra mot
-- fakturan. Efter den här migrationen kan inga NYA sådana rader uppstå.
DO $$
DECLARE
  v_repaired int;
BEGIN
  UPDATE public.orders
     SET fulfillment_status = 'shipped'
   WHERE status = 'shipped'
     AND fulfillment_status IN ('unfulfilled', 'picked', 'packed');
  GET DIAGNOSTICS v_repaired = ROW_COUNT;
  IF v_repaired > 0 THEN
    RAISE NOTICE '#249: flyttade leveransaxeln till fulfillment_status på % order(s)', v_repaired;
  END IF;
END $$;

-- ── LACKMUS ────────────────────────────────────────────────────────────────
-- Kör som service_role (eller en roll med inventory-åtkomst). Byt uuid:n mot
-- en riktig picking med order_id satt.
--
--   BEGIN;
--   -- 1. Utgångsläge: betald order som ännu inte skickats.
--   SELECT status, fulfillment_status, shipped_at, picked_at, packed_at
--     FROM orders WHERE id = '<order-uuid>';
--   --  paid | unfulfilled | NULL | NULL | NULL
--
--   SELECT public.ship_picking('<picking-uuid>');
--
--   -- 2. POSITIVT: leveransen landade på sin egen axel …
--   SELECT status, fulfillment_status, shipped_at IS NOT NULL AS stamped,
--          picked_at IS NOT NULL AS picked_stamped
--     FROM orders WHERE id = '<order-uuid>';
--   --  paid | shipped | t | t
--   --   ^^^^ REGRESSIONEN: står det 'shipped' här igen är buggen tillbaka.
--
--   -- 3. Omkörning är en no-op (pickingen är redan shipped), och en
--   --    already_shipped-retur får inte flytta någon axel:
--   SELECT public.ship_picking('<picking-uuid>');  -- {"already_shipped": true}
--
--   -- 4. NEGATIVT: en LEVERERAD order backas inte till 'shipped'.
--   UPDATE orders SET fulfillment_status = 'delivered' WHERE id = '<order-uuid>';
--   UPDATE picking_orders SET status = 'picked' WHERE id = '<picking-uuid>';
--   SELECT public.ship_picking('<picking-uuid>');
--   SELECT fulfillment_status FROM orders WHERE id = '<order-uuid>';  -- delivered
--   ROLLBACK;
--
-- Hela kedjan skarpt (så här hittades buggen, #248):
--   SELECT sandbox_seed_p2p(); SELECT sandbox_seed_o2c();
--   SELECT status, fulfillment_status FROM orders WHERE quote_id IS NOT NULL;
--   -- före: shipped | shipped      efter: paid | shipped
