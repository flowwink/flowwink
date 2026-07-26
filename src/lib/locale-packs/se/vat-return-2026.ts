/**
 * SKV 4700 (momsdeklaration) box map — SE, version 2026.
 *
 * This file used to hold its own copy of the map while the Deno edge handler
 * held another, because Deno cannot import from `src/`. The two drifted, and
 * the drift shipped real bugs: account 2611 (domestic 25% output VAT) was
 * summed as reverse charge, and box 21 mixed EU with non-EU service purchases
 * so a US SaaS subscription was reported as an EU acquisition.
 *
 * The map now lives in ONE place — `supabase/functions/_shared/locale/`, which
 * both runtimes can read because that file has no imports. This module is a
 * re-export so the frontend keeps a stable, idiomatic path.
 *
 * Change the map THERE, never here.
 */
export {
  SE_VAT_BOXES_2026,
  type BoxDef,
  type BoxKind,
} from '../../../../supabase/functions/_shared/locale/se-vat-boxes';

import { SE_VAT_BOXES_2026 } from '../../../../supabase/functions/_shared/locale/se-vat-boxes';

/** @deprecated Use `SE_VAT_BOXES_2026`. Kept for existing call sites. */
export const SE_VAT_RETURN_2026 = {
  version: '2026',
  form: 'SKV 4700',
  boxes: SE_VAT_BOXES_2026,
};
