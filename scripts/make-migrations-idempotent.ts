/**
 * Gör migrationerna omkörbara — engångstransformation, körd 2026-08-22.
 *
 * Varför: självprovisionering bygger på att integrationen kan AVBRYTAS och
 * återupptas. Om en migration applicerats men ledgerraden inte hann skrivas
 * (ledgern ljuger — nordbrygg hade 233 tabeller och 14 ledgerrader) så kör
 * omförsöket samma fil igen. Ett naket CREATE POLICY smäller då med
 * "already exists" och instansen är kilad för alltid. Repots egen regel i
 * CLAUDE.md säger att varje migration ska vara idempotent; 73 filer var det
 * inte.
 *
 * Transformationen är avsiktligt TRIVIAL och deterministisk:
 *   CREATE POLICY "x" ON t      →  DROP POLICY IF EXISTS "x" ON t; CREATE POLICY …
 *   CREATE [UNIQUE] INDEX y     →  CREATE [UNIQUE] INDEX IF NOT EXISTS y
 *   CREATE TRIGGER z ON t       →  DROP TRIGGER IF EXISTS z ON t; CREATE TRIGGER …
 *
 * Sluttillståndet ändras inte — det bevisas genom att jämföra ett fullständigt
 * schema-fingeravtryck (policies/kolumner/funktioner/index/triggers/grants)
 * före och efter en fresh replay. Diffen måste vara TOM.
 *
 * Satser inuti DO-block (EXECUTE format(...)) rörs INTE — de rapporteras i
 * stället, eftersom en textbaserad transformation inte kan resonera om dem.
 *
 * Kör: bun run scripts/make-migrations-idempotent.ts [--apply]
 */
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DIR = join(import.meta.dir ?? __dirname, '..', 'supabase', 'migrations');
const APPLY = process.argv.includes('--apply');

/**
 * Maskera allt regexarna inte får se INUTI, med bevarade offsets (blanksteg in,
 * radbrytningar kvar) så index-baserade insättningar hamnar rätt.
 *
 * Ordningen spelar roll: dollar-citat först (en kommentar inuti ett DO-block är
 * redan maskerad då), sedan blockkommentarer, sedan radkommentarer.
 *
 * Radkommentarer MÅSTE maskeras. Repots migrationer citerar rutinmässigt
 * SQL-satser i sina kommentarhuvuden ("-- CREATE POLICY ... ON tickets ...")
 * för att förklara vad de ersätter. Utan maskering genererar transformationen
 * skarpa DROP-satser ur prosa — första försöket dog på `relation "a" does not
 * exist`, ur en kommentar som beskrev en policy "ON a table".
 */
function maskUntouchable(sql: string): string {
  const blank = (m: string) => m.replace(/[^\n]/g, ' ');
  return sql
    .replace(/\$([A-Za-z_]\w*)?\$[\s\S]*?\$\1?\$/g, blank) // $$ … $$ / $tag$ … $tag$
    .replace(/\/\*[\s\S]*?\*\//g, blank)                    // /* … */
    .replace(/--[^\n]*/g, blank);                           // -- …
}

interface Report {
  file: string;
  policies: number;
  indexes: number;
  triggers: number;
  types: number;
  publications: number;
  constraints: number;
  skippedInDoBlock: number;
}

const reports: Report[] = [];

for (const file of readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()) {
  const path = join(DIR, file);
  const original = readFileSync(path, 'utf8');
  let sql = original;
  const masked = maskUntouchable(sql);

  // Vad som redan är avdroppat i filen — då rör vi det inte.
  const droppedPolicies = new Set(
    [...masked.matchAll(/DROP\s+POLICY\s+IF\s+EXISTS\s+("?)([^";\n]+?)\1\s+ON\s+([\w."]+)/gi)]
      .map((m) => `${m[2].trim()}@@${m[3].replace(/"/g, '').replace(/^public\./, '')}`),
  );
  const droppedTriggers = new Set(
    [...masked.matchAll(/DROP\s+TRIGGER\s+IF\s+EXISTS\s+(\w+)\s+ON\s+([\w."]+)/gi)]
      .map((m) => `${m[1]}@@${m[2].replace(/"/g, '').replace(/^public\./, '')}`),
  );

  let policies = 0;
  let indexes = 0;
  let triggers = 0;
  let types = 0;
  let publications = 0;
  let constraints = 0;
  let skippedInDoBlock = 0;

  // ── CREATE POLICY ────────────────────────────────────────────────────────
  // Matcha på det maskerade innehållet men skriv i originalet: samla träffar
  // med offset och applicera bakifrån så offsets håller.
  const polRe = /CREATE\s+POLICY\s+("?)([^";\n]+?)\1\s*(?:\n\s*)?ON\s+([\w."]+)/gi;
  const polHits: Array<{ index: number; name: string; table: string }> = [];
  for (const m of masked.matchAll(polRe)) {
    const name = m[2].trim();
    const table = m[3];
    const key = `${name}@@${table.replace(/"/g, '').replace(/^public\./, '')}`;
    if (droppedPolicies.has(key)) continue;
    polHits.push({ index: m.index!, name, table });
  }
  for (const hit of polHits.reverse()) {
    // Behåll indenteringen från raden CREATE POLICY står på.
    const lineStart = sql.lastIndexOf('\n', hit.index) + 1;
    const indent = sql.slice(lineStart, hit.index).match(/^\s*/)?.[0] ?? '';
    const quoted = /^[a-z_][a-z0-9_]*$/.test(hit.name) ? hit.name : `"${hit.name}"`;
    const drop = `${indent}DROP POLICY IF EXISTS ${quoted} ON ${hit.table};\n`;
    sql = sql.slice(0, lineStart) + drop + sql.slice(lineStart);
    policies++;
  }

  // ── CREATE INDEX ─────────────────────────────────────────────────────────
  const remasked = maskUntouchable(sql);
  const idxHits: Array<{ index: number; len: number; text: string }> = [];
  for (const m of remasked.matchAll(/CREATE\s+(UNIQUE\s+)?INDEX\s+(?!IF\s+NOT\s+EXISTS|CONCURRENTLY)/gi)) {
    idxHits.push({ index: m.index!, len: m[0].length, text: m[0] });
  }
  for (const hit of idxHits.reverse()) {
    sql = sql.slice(0, hit.index) + hit.text.replace(/INDEX\s*$/i, 'INDEX IF NOT EXISTS ') + sql.slice(hit.index + hit.len);
    indexes++;
  }

  // ── CREATE TRIGGER ───────────────────────────────────────────────────────
  const remasked2 = maskUntouchable(sql);
  const trgHits: Array<{ index: number; name: string; table: string }> = [];
  for (const m of remasked2.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?(?:CONSTRAINT\s+)?TRIGGER\s+(\w+)[\s\S]*?\sON\s+([\w."]+)/gi)) {
    const key = `${m[1]}@@${m[2].replace(/"/g, '').replace(/^public\./, '')}`;
    if (droppedTriggers.has(key)) continue;
    trgHits.push({ index: m.index!, name: m[1], table: m[2] });
  }
  for (const hit of trgHits.reverse()) {
    const lineStart = sql.lastIndexOf('\n', hit.index) + 1;
    const indent = sql.slice(lineStart, hit.index).match(/^\s*/)?.[0] ?? '';
    const drop = `${indent}DROP TRIGGER IF EXISTS ${hit.name} ON ${hit.table};\n`;
    sql = sql.slice(0, lineStart) + drop + sql.slice(lineStart);
    triggers++;
  }

  // ── CREATE TYPE ──────────────────────────────────────────────────────────
  // Postgres saknar CREATE TYPE IF NOT EXISTS. Kanoniska idiomet är att fånga
  // duplicate_object. Statementet sträcker sig till första ");" på egen rad
  // eller radslut — vi tar allt fram till nästa ";" utanför parenteser.
  const remasked3 = maskUntouchable(sql);
  const typeHits: Array<{ start: number; end: number }> = [];
  for (const m of remasked3.matchAll(/^CREATE\s+TYPE\s+[\s\S]*?;/gim)) {
    typeHits.push({ start: m.index!, end: m.index! + m[0].length });
  }
  for (const hit of typeHits.reverse()) {
    const stmt = sql.slice(hit.start, hit.end);
    const wrapped =
      `DO $idem$ BEGIN\n${stmt.replace(/^/gm, '  ')}\n` +
      `EXCEPTION WHEN duplicate_object THEN NULL;\nEND $idem$;`;
    sql = sql.slice(0, hit.start) + wrapped + sql.slice(hit.end);
    types++;
  }

  // ── ALTER PUBLICATION … ADD TABLE ────────────────────────────────────────
  // Samma idiom: att lägga till en tabell som redan är medlem ger
  // duplicate_object.
  const remasked4 = maskUntouchable(sql);
  const pubHits: Array<{ start: number; end: number }> = [];
  for (const m of remasked4.matchAll(/^ALTER\s+PUBLICATION\s+[\s\S]*?ADD\s+TABLE[\s\S]*?;/gim)) {
    pubHits.push({ start: m.index!, end: m.index! + m[0].length });
  }
  for (const hit of pubHits.reverse()) {
    const stmt = sql.slice(hit.start, hit.end);
    const wrapped =
      `DO $idem$ BEGIN\n${stmt.replace(/^/gm, '  ')}\n` +
      `EXCEPTION WHEN duplicate_object THEN NULL;\nEND $idem$;`;
    sql = sql.slice(0, hit.start) + wrapped + sql.slice(hit.end);
    publications++;
  }

  // ── ALTER TABLE … ADD CONSTRAINT ─────────────────────────────────────────
  // Postgres saknar ADD CONSTRAINT IF NOT EXISTS. Vid omkörning ger en
  // befintlig constraint duplicate_object, och en befintlig PK dessutom
  // invalid_table_definition ("multiple primary keys"). Båda fångas.
  const remasked5 = maskUntouchable(sql);
  const conHits: Array<{ start: number; end: number }> = [];
  for (const m of remasked5.matchAll(/^\s*ALTER\s+TABLE\s+(?:ONLY\s+)?[^;]*?ADD\s+CONSTRAINT[^;]*?;/gim)) {
    conHits.push({ start: m.index!, end: m.index! + m[0].length });
  }
  for (const hit of conHits.reverse()) {
    const stmt = sql.slice(hit.start, hit.end).replace(/^\n+/, '');
    const wrapped =
      `\nDO $idem$ BEGIN\n${stmt.replace(/^/gm, '  ')}\n` +
      `EXCEPTION WHEN duplicate_object OR invalid_table_definition OR duplicate_table THEN NULL;\nEND $idem$;`;
    sql = sql.slice(0, hit.start) + wrapped + sql.slice(hit.end);
    constraints++;
  }

  // Rapportera CREATE POLICY/TRIGGER inuti DO-block — orörda med flit.
  const inDo = (original.match(/\$([A-Za-z_]\w*)?\$[\s\S]*?\$\1?\$/g) ?? []).join('\n');
  skippedInDoBlock = (inDo.match(/CREATE\s+(POLICY|TRIGGER)\s/gi) ?? []).length;

  if (policies || indexes || triggers || types || publications || constraints || skippedInDoBlock) {
    reports.push({ file, policies, indexes, triggers, types, publications, constraints, skippedInDoBlock });
  }
  if (APPLY && sql !== original) writeFileSync(path, sql);
}

const tot = reports.reduce(
  (a, r) => ({
    p: a.p + r.policies,
    i: a.i + r.indexes,
    t: a.t + r.triggers,
    ty: a.ty + r.types,
    pu: a.pu + r.publications,
    c: a.c + r.constraints,
    s: a.s + r.skippedInDoBlock,
  }),
  { p: 0, i: 0, t: 0, ty: 0, pu: 0, c: 0, s: 0 },
);

for (const r of reports) {
  const bits = [
    r.policies ? `policy×${r.policies}` : '',
    r.indexes ? `index×${r.indexes}` : '',
    r.triggers ? `trigger×${r.triggers}` : '',
    r.types ? `type×${r.types}` : '',
    r.publications ? `publication×${r.publications}` : '',
    r.constraints ? `constraint×${r.constraints}` : '',
    r.skippedInDoBlock ? `DO-block(orörda)×${r.skippedInDoBlock}` : '',
  ].filter(Boolean).join(' ');
  console.log(`  ${r.file.slice(0, 56).padEnd(56)} ${bits}`);
}
console.log(
  `\n${APPLY ? 'SKRIVET' : 'TORRKÖRNING'}: ${reports.length} filer — ` +
    `${tot.p} policies, ${tot.i} index, ${tot.t} triggers, ${tot.ty} typer, ` +
    `${tot.pu} publications, ${tot.c} constraints gjorda omkörbara. ` +
    `${tot.s} satser i DO-block lämnade orörda.`,
);
