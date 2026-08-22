-- Beställningspunkten hade tre hem, och läsarna var oense (#247).
--
-- INCIDENTKLASSEN: samma storhet lagrad på tre ställen, med en läsare per hem.
-- Operatören satte min/max i lager-UI:t (useInventoryV2 → reorder_rules), och
-- procurement_run räknade på just den regeln. Men de AGENT-vända skillsen —
-- list_reorder_candidates (och purchase_reorder_check i agent-execute) —
-- rörde aldrig reorder_rules; de läste
--     COALESCE(product_stock.reorder_point, products.low_stock_threshold, 5).
-- Följden: det operatören ställde in syntes inte i agentens svar, och agenten
-- föreslog påfyllning på en tröskel ingen hade satt. Femman är samma form som
-- value_cents-fallbacken i abonnemangen: ett defaultvärde som ser ut som ett
-- svar. Och product_stock är dessutom den legacy-tabell som stock-chain-fixen
-- (20260820210006) redan hittade tom på varje instans — prioritetskedjan
-- började alltså i den svagaste källan.
--
-- BESLUTET: reorder_rules är kanonisk. Den matchar Odoos min/max-regel, den är
-- den UI:t redan skriver till, och den är den procurement_run redan läser. Alla
-- läsare pekas om dit. reorder_rules ligger per (product_id, location_id); de
-- produktnivå-svarande funktionerna här summerar därför de aktiva reglerna per
-- produkt — total minimikvantitet operatören bett oss hålla — och jämför mot
-- produktens totala saldo.
--
-- Reglerna tolkas LIKADANT som procurement_run gör, annars byter vi bara ett
-- oense par mot ett annat:
--   * bara is_active = true räknas;
--   * procurement_method väljer fil: 'buy' → inköpsförslag (list_reorder_
--     candidates), 'manufacture' → tillverkningsförslag (mrp_reorder_run). Har
--     produkten regler men ingen i den här filen, är den inte den här filens
--     jobb;
--   * en regel är ett MINIMUM: procurement_run agerar när saldot är UNDER
--     min_qty (strikt <), inte vid exakt min_qty. Regelbackade produkter jämförs
--     därför strikt. Den gamla produkttröskeln är en "lågt saldo vid eller
--     under"-markör och behåller sin inklusiva jämförelse;
--   * kvantiteten härleds som i procurement_run:
--     COALESCE(NULLIF(reorder_qty,0), max_qty − saldo), och om det blir ≤ 0:
--     min_qty − saldo;
--   * en uttrycklig regel ÄR operatörens ja — precis som procurement_run
--     frågar vi då inte product_stock.auto_reorder om lov. Den flaggan gäller
--     bara den regellösa fallback-filen.
--
-- PRODUKTER UTAN REGEL: kedjan är COALESCE(regelns min_qty,
-- product_stock.reorder_point, products.low_stock_threshold) — och den slutar
-- där. Ingen hårdkodad femma. product_stock.reorder_point finns kvar som
-- dokumenterad legacy-override för de instanser som faktiskt fyllde tabellen
-- (samma beslut som 20260820210006 tog för saldot); den är avvecklingsspår, inte
-- ett nytt hem. Saknar produkten BÅDE regel och tröskel är beställningspunkten
-- FRÅNVARANDE, inte 5 — och produkten föreslås inte alls. Ett golv ska i så fall
-- bli en synlig inställning, aldrig en literal i en funktionskropp.
--
-- SALDOT ändras inte här: det kommer fortsatt från products.stock_quantity med
-- product_stock som frivillig override, precis som stock-chain-fixen slog fast.
-- Undantaget är mrp_reorder_run, som SELECTade FROM product_stock och därför
-- svarade tomt på varje instans — den läser nu samma saldokälla som resten av
-- kedjan, annars vore trösklingen ovan ren teater.
--
-- Produkter UTAN regel har heller ingen deklarerad fil: fallback-kandidater kan
-- dyka upp i både inköps- och tillverkningsfilen (om produkten har en BOM). Det
-- är samma överlapp som fanns före den här migrationen, och exakt vad en regel
-- löser — därför lämnas det synligt i stället för att gissas bort.
--
-- BIFYND UNDER ARBETET: den kanoniska läsaren gick inte att köra. procurement_run
-- räknade inkommande kvantitet med
--     po.status IN ('draft','sent','confirmed','partial')
-- men 'partial' finns inte i enumet purchase_order_status (labeln heter
-- partially_received). Satsen kastar "invalid input value for enum" så fort det
-- finns EN aktiv regel att utvärdera — alltså har procurement_run aldrig kunnat
-- köra på en instans som faktiskt använder reorder_rules. Att peka om agenterna
-- till en läsare som själv smäller vore att flytta problemet, så labeln rättas
-- här. Kroppen är i övrigt oförändrad (hämtad live, återlagd orörd).
--
-- Omkörbar: enbart CREATE OR REPLACE FUNCTION + COMMENT.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. list_reorder_candidates — inköpsfilen (procurement_method = 'buy')
--    Konsumeras av skillen med samma namn OCH av auto_generate_purchase_orders,
--    som därmed ärver fixen utan egen ändring.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_reorder_candidates()
RETURNS TABLE(
  product_id uuid,
  product_name text,
  quantity_on_hand integer,
  reorder_point integer,
  reorder_quantity integer,
  vendor_id uuid,
  vendor_name text,
  unit_price_cents integer,
  lead_time_days integer,
  min_order_quantity integer,
  estimated_cost_cents bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH rule AS (
    SELECT
      rr.product_id,
      COUNT(*)                                                            AS rules_total,
      COUNT(*) FILTER (WHERE rr.procurement_method = 'buy')               AS buy_rules,
      SUM(rr.min_qty) FILTER (WHERE rr.procurement_method = 'buy')        AS min_qty,
      SUM(rr.max_qty) FILTER (WHERE rr.procurement_method = 'buy')        AS max_qty,
      SUM(COALESCE(rr.reorder_qty, 0))
        FILTER (WHERE rr.procurement_method = 'buy')                      AS reorder_qty
    FROM public.reorder_rules rr
    WHERE rr.is_active = true
    GROUP BY rr.product_id
  ),
  candidate AS (
    SELECT
      p.id,
      p.name,
      COALESCE(ps.quantity_on_hand, p.stock_quantity, 0)::int AS on_hand,
      (COALESCE(r.buy_rules, 0) > 0)                          AS has_rule,
      COALESCE(r.rules_total, 0)                              AS rules_total,
      -- Beställningspunkten: regeln först, legacy-override, produkttröskel.
      -- NULL = ingen tröskel satt någonstans → produkten föreslås inte.
      COALESCE(r.min_qty, ps.reorder_point, p.low_stock_threshold)::numeric AS rp,
      CASE
        WHEN COALESCE(r.buy_rules, 0) > 0 THEN
          -- Samma härledning som procurement_run.
          COALESCE(
            NULLIF(r.reorder_qty, 0),
            NULLIF(GREATEST(r.max_qty - COALESCE(ps.quantity_on_hand, p.stock_quantity, 0), 0), 0),
            r.min_qty - COALESCE(ps.quantity_on_hand, p.stock_quantity, 0)
          )
        ELSE
          COALESCE(
            NULLIF(ps.reorder_quantity, 0),
            GREATEST(p.low_stock_threshold * 3, 10)
          )
      END::numeric                                            AS rq,
      COALESCE(ps.auto_reorder, true)                         AS auto_reorder
    FROM public.products p
    LEFT JOIN public.product_stock ps ON ps.product_id = p.id
    LEFT JOIN rule r ON r.product_id = p.id
    WHERE p.is_active = true
      AND p.track_inventory = true
  )
  SELECT
    c.id,
    c.name,
    c.on_hand,
    CEIL(c.rp)::int,
    GREATEST(CEIL(c.rq), COALESCE(vp.min_order_quantity, 1))::int,
    vp.vendor_id,
    v.name,
    vp.unit_price_cents,
    vp.lead_time_days,
    vp.min_order_quantity,
    GREATEST(CEIL(c.rq), COALESCE(vp.min_order_quantity, 1))::bigint
      * COALESCE(vp.unit_price_cents, 0)::bigint
  FROM candidate c
  LEFT JOIN public.vendor_products vp ON vp.product_id = c.id AND vp.is_preferred = true
  LEFT JOIN public.vendors v ON v.id = vp.vendor_id AND v.is_active = true
  WHERE c.rp IS NOT NULL
    AND CASE
          WHEN c.has_rule THEN c.on_hand < c.rp
          ELSE c.rules_total = 0 AND c.auto_reorder AND c.on_hand <= c.rp
        END
  ORDER BY (c.rp - c.on_hand) DESC;
$function$;

COMMENT ON FUNCTION public.list_reorder_candidates() IS
  'Produkter som behöver köpas in, med föredragen leverantörs pris. Beställningspunkten kommer från reorder_rules (aktiva regler med procurement_method=buy, summerade per produkt) — samma källa och samma tolkning som procurement_run. Utan regel: product_stock.reorder_point (legacy) eller products.low_stock_threshold; utan tröskel någonstans föreslås produkten inte. Saldo från products.stock_quantity med product_stock som frivillig override.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. mrp_reorder_run — tillverkningsfilen (procurement_method = 'manufacture')
--    Läste både tröskel OCH saldo ur den tomma product_stock; nu samma
--    regelkälla som ovan och samma saldokälla som resten av lagerkedjan.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mrp_reorder_run(p_dry_run boolean DEFAULT true)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_candidates jsonb := '[]'::jsonb;
  v_created int := 0;
  v_mo uuid;
BEGIN
  IF NOT p_dry_run AND NOT (auth.role() = 'service_role' OR can_access_module(auth.uid(),'manufacturing')) THEN
    RAISE EXCEPTION 'Requires the manufacturing module — an admin can grant it under Users → Role Permissions';
  END IF;

  FOR v_row IN
    WITH rule AS (
      SELECT
        rr.product_id,
        COUNT(*)                                                                AS rules_total,
        COUNT(*) FILTER (WHERE rr.procurement_method = 'manufacture')           AS mfg_rules,
        SUM(rr.min_qty) FILTER (WHERE rr.procurement_method = 'manufacture')    AS min_qty,
        SUM(rr.max_qty) FILTER (WHERE rr.procurement_method = 'manufacture')    AS max_qty,
        SUM(COALESCE(rr.reorder_qty, 0))
          FILTER (WHERE rr.procurement_method = 'manufacture')                  AS reorder_qty
      FROM reorder_rules rr
      WHERE rr.is_active = true
      GROUP BY rr.product_id
    ),
    candidate AS (
      SELECT
        p.id                                                      AS product_id,
        p.name                                                    AS product_name,
        COALESCE(ps.quantity_on_hand, p.stock_quantity, 0)::int   AS on_hand,
        (COALESCE(r.mfg_rules, 0) > 0)                            AS has_rule,
        COALESCE(r.rules_total, 0)                                AS rules_total,
        COALESCE(r.min_qty, ps.reorder_point, p.low_stock_threshold)::numeric AS rp,
        CASE
          WHEN COALESCE(r.mfg_rules, 0) > 0 THEN
            COALESCE(
              NULLIF(r.reorder_qty, 0),
              NULLIF(GREATEST(r.max_qty - COALESCE(ps.quantity_on_hand, p.stock_quantity, 0), 0), 0),
              r.min_qty - COALESCE(ps.quantity_on_hand, p.stock_quantity, 0)
            )
          ELSE NULL
        END::numeric                                              AS rule_qty,
        b.id                                                      AS bom_id
      FROM products p
      JOIN bom_headers b ON b.product_id = p.id AND b.is_active
      LEFT JOIN product_stock ps ON ps.product_id = p.id
      LEFT JOIN rule r ON r.product_id = p.id
    )
    SELECT
      c.product_id,
      c.product_name,
      c.on_hand                                                   AS quantity_on_hand,
      CEIL(c.rp)::int                                             AS reorder_point,
      GREATEST(CEIL(COALESCE(c.rule_qty, c.rp - c.on_hand)), 1)::int AS suggested_qty,
      c.bom_id
    FROM candidate c
    WHERE c.rp IS NOT NULL
      AND c.rp > 0
      AND CASE
            WHEN c.has_rule THEN c.on_hand < c.rp
            ELSE c.rules_total = 0 AND c.on_hand <= c.rp
          END
      AND NOT EXISTS (
        SELECT 1 FROM manufacturing_orders mo
        WHERE mo.product_id = c.product_id AND mo.status NOT IN ('done','cancelled')
      )
  LOOP
    v_candidates := v_candidates || jsonb_build_object(
      'product_id', v_row.product_id, 'product_name', v_row.product_name,
      'quantity_on_hand', v_row.quantity_on_hand, 'reorder_point', v_row.reorder_point,
      'suggested_qty', v_row.suggested_qty, 'bom_id', v_row.bom_id);

    IF NOT p_dry_run THEN
      INSERT INTO manufacturing_orders (mo_number, product_id, bom_id, quantity, status, source_type, created_by)
      VALUES (next_mo_number(), v_row.product_id, v_row.bom_id, v_row.suggested_qty, 'draft', 'reorder', auth.uid())
      RETURNING id INTO v_mo;
      v_created := v_created + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'dry_run', p_dry_run,
    'candidate_count', jsonb_array_length(v_candidates),
    'created', v_created,
    'candidates', v_candidates
  );
END;
$function$;

COMMENT ON FUNCTION public.mrp_reorder_run(boolean) IS
  'Tillverkade produkter (aktiv BOM) under sin beställningspunkt, utan öppen MO. Tröskeln kommer från reorder_rules (aktiva regler med procurement_method=manufacture) — har produkten bara inköpsregler är den inköpsfilens jobb. Utan regel: product_stock.reorder_point (legacy) eller products.low_stock_threshold; utan tröskel någonstans skapas inget förslag. Saldo från products.stock_quantity med product_stock som frivillig override.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. procurement_run — den kanoniska läsaren, som inte gick att köra
--    Enda ändringen: 'partial' → 'partially_received' (giltig enum-label).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.procurement_run()
RETURNS TABLE(suggestions_created integer, rules_evaluated integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_rule record; v_on_hand numeric; v_reserved numeric; v_incoming numeric; v_virtual numeric; v_qty_to_order numeric; v_count integer := 0; v_evaluated integer := 0;
BEGIN
  IF NOT ((auth.role() = 'service_role' OR can_access_module(auth.uid(),'inventory'))) THEN RAISE EXCEPTION 'Insufficient privileges'; END IF;
  FOR v_rule IN SELECT * FROM reorder_rules WHERE is_active = true LOOP
    v_evaluated := v_evaluated + 1;
    SELECT COALESCE(SUM(quantity),0), COALESCE(SUM(reserved_quantity),0) INTO v_on_hand, v_reserved
      FROM stock_quants WHERE product_id = v_rule.product_id AND location_id = v_rule.location_id;
    SELECT COALESCE(SUM(pol.quantity - COALESCE(pol.received_quantity,0)),0) INTO v_incoming
      FROM purchase_order_lines pol JOIN purchase_orders po ON po.id = pol.purchase_order_id
      WHERE pol.product_id = v_rule.product_id AND po.status IN ('draft','sent','confirmed','partially_received');
    v_virtual := v_on_hand - v_reserved + COALESCE(v_incoming,0);
    IF v_virtual < v_rule.min_qty THEN
      v_qty_to_order := COALESCE(NULLIF(v_rule.reorder_qty,0), v_rule.max_qty - v_virtual);
      IF v_qty_to_order <= 0 THEN v_qty_to_order := v_rule.min_qty - v_virtual; END IF;
      IF NOT EXISTS (SELECT 1 FROM procurement_suggestions WHERE product_id = v_rule.product_id AND location_id = v_rule.location_id AND status = 'pending') THEN
        INSERT INTO procurement_suggestions (product_id, location_id, suggested_qty, procurement_method, preferred_vendor_id, needed_by, reasoning)
        VALUES (v_rule.product_id, v_rule.location_id, v_qty_to_order, v_rule.procurement_method, v_rule.preferred_vendor_id,
          (CURRENT_DATE + (v_rule.lead_time_days || ' days')::interval)::date,
          jsonb_build_object('on_hand', v_on_hand, 'reserved', v_reserved, 'incoming', v_incoming, 'virtual', v_virtual, 'min_qty', v_rule.min_qty, 'max_qty', v_rule.max_qty));
        v_count := v_count + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN QUERY SELECT v_count, v_evaluated;
END; $function$;

COMMENT ON FUNCTION public.procurement_run() IS
  'Utvärderar alla aktiva reorder_rules per (produkt, lagerplats) mot virtuellt saldo (on hand − reserverat + inkommande) och skapar procurement_suggestions. Kanonisk läsare av beställningspunkten; agentskillsen tolkar samma regler likadant sedan #247.';
