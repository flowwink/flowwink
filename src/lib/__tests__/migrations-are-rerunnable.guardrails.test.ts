import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Spärr: varje migration måste gå att KÖRA OM.
 *
 * Självprovisionering (admin pekar sin Supabase på repot, integrationen kör
 * migrationerna) bygger på att leveransen kan AVBRYTAS och återupptas. Om en
 * migration hann appliceras men ledgerraden inte skrevs, kör omförsöket samma
 * fil igen. Är filen inte omkörbar smäller den med "already exists" — och
 * instansen är kilad för alltid, för varje nytt försök dör på samma sats.
 *
 * Det hände på riktigt (nordbrygg, 2026-08-22): 233 tabeller i databasen mot
 * 14 rader i ledgern, och integrationens branch stod på MIGRATIONS_FAILED.
 * Den felande satsen var ett naket
 *   CREATE POLICY "Admins can insert messages in any conversation" ON chat_messages
 * i 20260616190010. Repots egen regel i CLAUDE.md sa redan att migrationer ska
 * vara idempotenta; 30 filer var det inte. 1674 satser åtgärdades i
 * 20260822 (se scripts/make-migrations-idempotent.ts), verifierat genom att
 * köra hela kedjan två gånger mot samma databas: 482/482 rena.
 *
 * Den här spärren fäller nästa. Mönstren:
 *   CREATE POLICY            → DROP POLICY IF EXISTS först
 *   CREATE [UNIQUE] INDEX    → IF NOT EXISTS
 *   CREATE TRIGGER           → DROP TRIGGER IF EXISTS först
 *   CREATE TYPE              → DO-block som fångar duplicate_object
 *   ALTER TABLE ADD CONSTRAINT / ALTER PUBLICATION ADD TABLE → samma DO-idiom
 *
 * Satser inuti DO-block räknas som skyddade — där kan författaren uttrycka sitt
 * eget villkor, och en textbaserad spärr kan inte resonera om det.
 */

const DIR = join(__dirname, '../../../supabase/migrations');

/** Maskera dollar-citat och kommentarer, med bevarade radbrytningar. */
function mask(sql: string): string {
  const blank = (m: string) => m.replace(/[^\n]/g, ' ');
  return sql
    .replace(/\$([A-Za-z_]\w*)?\$[\s\S]*?\$\1?\$/g, blank)
    .replace(/\/\*[\s\S]*?\*\//g, blank)
    .replace(/--[^\n]*/g, blank);
}

interface Offence {
  file: string;
  kind: string;
  detail: string;
}

function scan(): Offence[] {
  const out: Offence[] = [];
  for (const file of readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()) {
    const sql = mask(readFileSync(join(DIR, file), 'utf8'));

    const droppedPolicies = new Set(
      [...sql.matchAll(/DROP\s+POLICY\s+IF\s+EXISTS\s+("?)([^";\n]+?)\1\s+ON\s+([\w."]+)/gi)]
        .map((m) => `${m[2].trim()}@@${m[3].replace(/"/g, '').replace(/^public\./, '')}`),
    );
    for (const m of sql.matchAll(/CREATE\s+POLICY\s+("?)([^";\n]+?)\1\s*(?:\n\s*)?ON\s+([\w."]+)/gi)) {
      const key = `${m[2].trim()}@@${m[3].replace(/"/g, '').replace(/^public\./, '')}`;
      if (!droppedPolicies.has(key)) {
        out.push({ file, kind: 'CREATE POLICY utan DROP POLICY IF EXISTS', detail: m[2].trim() });
      }
    }

    const droppedTriggers = new Set(
      [...sql.matchAll(/DROP\s+TRIGGER\s+IF\s+EXISTS\s+(\w+)\s+ON\s+([\w."]+)/gi)]
        .map((m) => `${m[1]}@@${m[2].replace(/"/g, '').replace(/^public\./, '')}`),
    );
    for (const m of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?(?:CONSTRAINT\s+)?TRIGGER\s+(\w+)[\s\S]*?\sON\s+([\w."]+)/gi)) {
      const key = `${m[1]}@@${m[2].replace(/"/g, '').replace(/^public\./, '')}`;
      if (!droppedTriggers.has(key)) {
        out.push({ file, kind: 'CREATE TRIGGER utan DROP TRIGGER IF EXISTS', detail: m[1] });
      }
    }

    for (const m of sql.matchAll(/CREATE\s+(UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS|CONCURRENTLY)(\w+)?/gi)) {
      out.push({ file, kind: 'CREATE INDEX utan IF NOT EXISTS', detail: m[2] ?? '?' });
    }
    for (const m of sql.matchAll(/^CREATE\s+TYPE\s+([\w."]+)/gim)) {
      out.push({ file, kind: 'CREATE TYPE utanför DO-block', detail: m[1] });
    }
    for (const m of sql.matchAll(/^\s*ALTER\s+TABLE\s+(?:ONLY\s+)?[^;]*?ADD\s+CONSTRAINT\s+("?)([\w]+)\1/gim)) {
      out.push({ file, kind: 'ADD CONSTRAINT utanför DO-block', detail: m[2] });
    }
    for (const m of sql.matchAll(/^ALTER\s+PUBLICATION\s+(\w+)[^;]*?ADD\s+TABLE/gim)) {
      out.push({ file, kind: 'ALTER PUBLICATION ADD TABLE utanför DO-block', detail: m[1] });
    }
  }
  return out;
}

describe('migrationer går att köra om', () => {
  it('hittar migrationerna alls (annars mäter testet ingenting)', () => {
    const files = readdirSync(DIR).filter((f) => f.endsWith('.sql'));
    expect(files.length).toBeGreaterThan(400);
  });

  it('ingen migration bär DDL som smäller vid omkörning', () => {
    const offences = scan();
    const summary = offences
      .slice(0, 25)
      .map((o) => `  ${o.file} — ${o.kind}: ${o.detail}`)
      .join('\n');
    expect(
      offences,
      `Dessa satser gör migrationen icke-omkörbar. En avbruten provisionering ` +
        `som återupptas kör filen igen, satsen smäller på "already exists", och ` +
        `instansen kilas permanent — det var nordbryggs fel 2026-08-22.\n` +
        `Skyddsmönstren står i testets huvudkommentar; ` +
        `scripts/make-migrations-idempotent.ts gör transformationen ` +
        `mekaniskt.\n${summary}${offences.length > 25 ? `\n  … och ${offences.length - 25} till` : ''}`,
    ).toEqual([]);
  });
});
