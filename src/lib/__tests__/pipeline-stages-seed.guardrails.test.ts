import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Pipeline stages are PLATFORM CONFIG and must exist on every instance.
 *
 * Found by a fleet sweep (2026-08-08): dev and the sandbox had pipeline_stages
 * completely empty — all three entity types — while the other instances carried
 * the full 17. Both had the original seeding migration in their ledger, so the
 * rows had been created and later lost. Empty stages means empty kanbans, and
 * (since the same day's "one truth" change) stage dropdowns and pipeline stats
 * silently falling back to hardcoded lists.
 *
 * Same class as the role_module_access_defaults incident: platform config MUST
 * be seeded and re-assertable; business config (carriers, approval rules) is
 * correctly born empty.
 */

const seed = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/20260808390000_seed-pipeline-stages-platform-config.sql'),
  'utf-8');

describe('the seed covers the whole platform surface', () => {
  it('seeds all three entity types the table supports', () => {
    for (const entity of ["'deal'", "'lead'", "'ticket'"]) {
      expect(seed).toContain(`(${entity},`);
    }
  });

  it('carries the full deal pipeline including prospecting', () => {
    for (const key of ['lead', 'prospecting', 'qualified', 'proposal', 'negotiation', 'closed_won', 'closed_lost']) {
      expect(seed).toContain(`('deal','${key}'`);
    }
  });

  it('marks won/lost so "open" is derivable — the stats depend on it', () => {
    expect(seed).toMatch(/\('deal','closed_won','Closed Won',60,100::numeric,true,false,false\)/);
    expect(seed).toMatch(/\('deal','closed_lost','Closed Lost',70,0::numeric,false,true,true\)/);
  });
});

describe('re-asserting config never destroys operator customisation', () => {
  it('inserts only genuinely missing (entity_type, key) pairs', () => {
    expect(seed).toMatch(/WHERE NOT EXISTS \(\s*SELECT 1 FROM public\.pipeline_stages p\s*WHERE p\.entity_type = d\.entity_type AND p\.key = d\.key/);
  });

  it('never updates, deletes or truncates an existing stage', () => {
    // A renamed stage, a changed probability or a deactivated stage must
    // survive every future run of this seed.
    const code = seed.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
    expect(code).not.toMatch(/\bUPDATE\s+public\.pipeline_stages/i);
    expect(code).not.toMatch(/\bDELETE\s+FROM\s+public\.pipeline_stages/i);
    expect(code).not.toMatch(/\bTRUNCATE\b/i);
    expect(code).not.toMatch(/ON CONFLICT[\s\S]{0,40}DO UPDATE/i);
  });

  it('leaves a callable function behind so a rebuild can re-assert without a migration replay', () => {
    expect(seed).toMatch(/CREATE OR REPLACE FUNCTION public\.seed_default_pipeline_stages\(\)/);
    expect(seed).toMatch(/GRANT EXECUTE ON FUNCTION public\.seed_default_pipeline_stages\(\) TO service_role/);
    expect(seed).toMatch(/SELECT public\.seed_default_pipeline_stages\(\);/);
  });

  it('reports how many rows it inserted — a silent seed cannot be verified', () => {
    expect(seed).toMatch(/GET DIAGNOSTICS v_count = ROW_COUNT/);
  });
});
