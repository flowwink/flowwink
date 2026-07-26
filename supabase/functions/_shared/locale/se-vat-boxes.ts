// SKV 4700 (momsdeklaration) box map — THE single source of truth.
//
// Lives in _shared/ deliberately: the Deno edge handler cannot import from
// src/, so this map used to be duplicated — once in the handler and once in
// src/lib/locale-packs/se/vat-return-2026.ts. The two drifted, and the drift
// was a real bug: the SQL path summed account 2611 as "reverse charge" (2611
// is domestic 25% output VAT), and box 21 mixed EU and non-EU service
// purchases. One copy cannot drift from itself.
//
// This file has NO imports on purpose — that is what lets both the Deno
// runtime and the Vite/vitest side read it.
//
// Verify the account/box mapping with an accountant before filing.

export type BoxKind =
  | 'output_vat' | 'input_vat'
  | 'base_from_vat' | 'base_credit' | 'base_debit'
  | 'computed';

export interface BoxDef {
  code: string;
  label: string;
  kind: BoxKind;
  accounts?: string[];
  derive_from?: { box: string; rate: number }[];
  formula?: Record<string, 1 | -1>;
}

export const SE_VAT_BOXES_2026: BoxDef[] = [
  { code: '05', label: 'Momspliktig försäljning ex moms', kind: 'base_from_vat',
    derive_from: [{ box: '10', rate: 0.25 }, { box: '11', rate: 0.12 }, { box: '12', rate: 0.06 }] },

  { code: '20', label: 'Inköp av varor från annat EU-land', kind: 'base_debit',
    accounts: ['4515','4516','4517','4518'] },
  // BAS 4535-4538 = services from another EU country; 4531-4534 = services
  // from OUTSIDE the EU. Box 21 previously summed both ranges, reporting a US
  // purchase as an EU acquisition and leaving box 22 empty.
  { code: '21', label: 'Inköp av tjänster från annat EU-land enligt huvudregeln', kind: 'base_debit',
    accounts: ['4535','4536','4537','4538'] },
  { code: '22', label: 'Inköp av tjänster från land utanför EU', kind: 'base_debit',
    accounts: ['4531','4532','4533','4534'] },
  { code: '50', label: 'Beskattningsunderlag vid import', kind: 'base_debit',
    accounts: ['4545','4546','4547'] },

  { code: '35', label: 'Försäljning av varor till annat EU-land', kind: 'base_credit',
    accounts: ['3105','3106','3108'] },
  { code: '39', label: 'Försäljning av tjänster till annat EU-land', kind: 'base_credit',
    accounts: ['3308'] },
  { code: '41', label: 'Försäljning utanför EU (export)', kind: 'base_credit',
    accounts: ['3305','3306'] },

  { code: '10', label: 'Utgående moms 25%', kind: 'output_vat',
    accounts: ['2610','2611','2612','2613','2616','2617','2618','2619'] },
  { code: '11', label: 'Utgående moms 12%', kind: 'output_vat',
    accounts: ['2620','2621','2622','2623','2626','2627','2628','2629'] },
  { code: '12', label: 'Utgående moms 6%', kind: 'output_vat',
    accounts: ['2630','2631','2632','2633','2636','2637','2638','2639'] },

  { code: '30', label: 'Utgående moms 25% på EU-förvärv / omvänd skattskyldighet',
    kind: 'output_vat', accounts: ['2614','2615'] },
  { code: '31', label: 'Utgående moms 12% på EU-förvärv / omvänd skattskyldighet',
    kind: 'output_vat', accounts: ['2624','2625'] },
  { code: '32', label: 'Utgående moms 6% på EU-förvärv / omvänd skattskyldighet',
    kind: 'output_vat', accounts: ['2634','2635'] },

  { code: '48', label: 'Ingående moms att dra av', kind: 'input_vat',
    accounts: ['2640','2641','2642','2643','2644','2645','2646','2647','2648','2649'] },

  { code: '49', label: 'Moms att betala (+) / få tillbaka (−)', kind: 'computed',
    formula: { '10': 1, '11': 1, '12': 1, '30': 1, '31': 1, '32': 1, '48': -1 } },
];
