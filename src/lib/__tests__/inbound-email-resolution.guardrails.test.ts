import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  bareEmail,
  threadKey,
  resolveInboundEntity,
} from '../../../supabase/functions/_shared/email/resolve-entity';

/**
 * Inbound mail binds to a customer by thread first and sender second. Two things
 * make this fragile enough to pin down:
 *
 *  - threadKey must normalise exactly as trg_touch_email_thread does, or the
 *    lookup misses the row the trigger wrote and every reply reads as new.
 *  - The resolver must never guess. An unattached message is visible and can be
 *    linked by hand; a wrongly attached one is a falsehood in a customer's
 *    history that nobody thinks to re-check.
 */

/**
 * Minimal stand-in for the query builder. A table's value may be a plain row or
 * a function of the filters applied, which is what lets a test say "the lead
 * with THIS id has THIS address" — the question the subject fallback now has to
 * ask before it trusts a match.
 */
type TableSpec = unknown | ((filters: Record<string, unknown>) => unknown);

function fakeDb(tables: Record<string, TableSpec>) {
  return {
    from(table: string) {
      const filters: Record<string, unknown> = {};
      const chain: Record<string, unknown> = {
        select: () => chain,
        eq: (col: string, val: unknown) => { filters[col] = val; return chain; },
        ilike: (col: string, val: unknown) => { filters[col] = val; return chain; },
        maybeSingle: async () => {
          const spec = tables[table];
          const row = typeof spec === 'function' ? spec(filters) : spec;
          return { data: row ?? null, error: null };
        },
      };
      return chain;
    },
  };
}

describe('bareEmail', () => {
  it('unwraps a display-name address', () => {
    expect(bareEmail('Elin Marklund <elin@example.com>')).toBe('elin@example.com');
  });

  it('lowercases, because addresses are matched case-insensitively', () => {
    expect(bareEmail('Elin@Example.COM')).toBe('elin@example.com');
  });

  it('returns null rather than an empty string for nothing', () => {
    expect(bareEmail(null)).toBeNull();
    expect(bareEmail('  ')).toBeNull();
  });
});

describe('threadKey mirrors the DB trigger', () => {
  it('prefers the provider thread id when there is one', () => {
    expect(threadKey('Re: anything', 'gmail-thread-123')).toBe('gmail-thread-123');
  });

  it('strips Re:/Fwd:/Fw: and lowercases when falling back to the subject', () => {
    expect(threadKey('Re: Offert till Nordic FieldOps', null)).toBe('offert till nordic fieldops');
    expect(threadKey('Fwd: Offert till Nordic FieldOps', null)).toBe('offert till nordic fieldops');
    expect(threadKey('FW: Offert till Nordic FieldOps', null)).toBe('offert till nordic fieldops');
  });

  it('lands a reply on the same key as the message it answers', () => {
    expect(threadKey('Re: Kickoff', null)).toBe(threadKey('Kickoff', null));
  });

  it('is null when there is nothing to key on', () => {
    expect(threadKey(null, null)).toBeNull();
    expect(threadKey('', null)).toBeNull();
  });

  it('uses the same rule as public.normalize_thread_key', () => {
    // The DB function is the other half of this contract: it writes the
    // thread_key we look up. If its normalisation changes and this does not,
    // every reply reads as a brand-new conversation and lands unattached.
    const sql = readFileSync(
      resolve(
        __dirname,
        '../../../supabase/migrations/20260708132027_dad92616-b484-4d2f-a194-9701dcaf331b.sql',
      ),
      'utf-8',
    );
    const body = sql.slice(sql.indexOf('FUNCTION public.normalize_thread_key'));
    // Same prefixes, same flags, and lower() applied to the subject branch only —
    // a provider thread id is opaque and must not be case-folded.
    expect(body).toContain("'^(re:|fwd:|fw:)\\s*', '', 'ig'");
    expect(body.slice(0, 400)).toMatch(/lower\(regexp_replace\(coalesce\(p_subject/);
    expect(body.slice(0, 400)).toMatch(/coalesce\(\s*nullif\(p_thread_id/);
  });
});

describe('resolveInboundEntity', () => {
  const from = { sender: 'elin@example.com', subject: 'Re: Kickoff', threadId: 't-1' };

  it('inherits the thread we started — the only certain signal', async () => {
    const db = fakeDb({
      email_threads: { related_entity_type: 'lead', related_entity_id: 'lead-1' },
      leads: { id: 'someone-else' },
    });
    const r = await resolveInboundEntity(db, from);
    expect(r).toEqual({
      related_entity_type: 'lead',
      related_entity_id: 'lead-1',
      resolved_by: 'thread',
    });
  });

  it('falls back to the sender address when no thread matches', async () => {
    const db = fakeDb({ email_threads: null, leads: { id: 'lead-2' } });
    const r = await resolveInboundEntity(db, from);
    expect(r.related_entity_id).toBe('lead-2');
    expect(r.resolved_by).toBe('lead_email');
  });

  it('then tries company contacts', async () => {
    const db = fakeDb({ email_threads: null, leads: null, company_contacts: { id: 'contact-1' } });
    const r = await resolveInboundEntity(db, from);
    expect(r.related_entity_type).toBe('company_contact');
    expect(r.resolved_by).toBe('company_contact');
  });

  it('leaves an unknown sender unattached instead of guessing', async () => {
    const db = fakeDb({ email_threads: null, leads: null, company_contacts: null });
    const r = await resolveInboundEntity(db, from);
    expect(r.related_entity_id).toBeNull();
    expect(r.resolved_by).toBe('unresolved');
  });

  it('does not attach a message with no sender at all', async () => {
    const db = fakeDb({ email_threads: null, leads: { id: 'lead-3' } });
    const r = await resolveInboundEntity(db, { sender: null, subject: null, threadId: null });
    expect(r.related_entity_id).toBeNull();
  });
});

/**
 * Composio's send does not always return a gmail thread id, so our outbound row
 * gets keyed by subject while the reply carries a real one. Without a subject
 * fallback those halves never meet — Elin's first reply landed unattached for
 * exactly this reason and had to be linked by hand.
 *
 * But a subject is neither unique nor ours. "Offert", "Faktura" and "Hej" recur
 * across every customer a business has, so the fallback is only allowed to
 * decide when the sender is the person that thread belongs to.
 */
describe('subject fallback requires the sender to match', () => {
  const reply = { sender: 'elin@example.com', subject: 'Re: Offert', threadId: 'gmail-thread-999' };
  const threadOwnedByElin = { related_entity_type: 'lead', related_entity_id: 'lead-elin' };

  /** Thread found by subject only; the gmail thread id is unknown to us. */
  const bySubjectOnly = (thread: unknown) => (f: Record<string, unknown>) =>
    f.thread_key === 'offert' ? thread : null;

  it('binds when the sender is the lead the thread belongs to', async () => {
    const db = fakeDb({
      email_threads: bySubjectOnly(threadOwnedByElin),
      leads: (f) => (f.id === 'lead-elin' && f.email === 'elin@example.com' ? { id: 'lead-elin' } : null),
    });
    const r = await resolveInboundEntity(db, reply);
    expect(r).toEqual({
      related_entity_type: 'lead',
      related_entity_id: 'lead-elin',
      resolved_by: 'thread_subject',
    });
  });

  it('refuses when a DIFFERENT customer replies with the same subject', async () => {
    // The thread belongs to Elin. Björn, unrelated, sends "Re: Offert".
    const db = fakeDb({
      email_threads: bySubjectOnly(threadOwnedByElin),
      // Elin's lead does not carry Björn's address, and Björn is unknown to us.
      leads: () => null,
      company_contacts: () => null,
    });
    const r = await resolveInboundEntity(db, { ...reply, sender: 'bjorn@other-company.example' });
    expect(r.related_entity_id).toBeNull();
    expect(r.resolved_by).toBe('unresolved');
  });

  it('lets the address decide on its own merits after a rejected subject match', async () => {
    const db = fakeDb({
      email_threads: bySubjectOnly(threadOwnedByElin),
      // Sender is not Elin, but IS a lead in their own right.
      leads: (f) => (f.id ? null : { id: 'lead-bjorn' }),
    });
    const r = await resolveInboundEntity(db, { ...reply, sender: 'bjorn@other-company.example' });
    expect(r.related_entity_id).toBe('lead-bjorn');
    expect(r.resolved_by).toBe('lead_email');
  });

  it('does not trust a subject match on an entity it cannot verify', async () => {
    // An invoice thread has no address to check the sender against.
    const db = fakeDb({
      email_threads: bySubjectOnly({ related_entity_type: 'invoice', related_entity_id: 'inv-1' }),
      leads: () => null,
      company_contacts: () => null,
    });
    const r = await resolveInboundEntity(db, reply);
    expect(r.resolved_by).toBe('unresolved');
  });

  it('still trusts the provider thread id without any sender check', async () => {
    // This binding is one WE wrote when sending, so it needs no corroboration.
    const db = fakeDb({
      email_threads: (f) => (f.thread_key === 'gmail-thread-999' ? threadOwnedByElin : null),
      leads: () => null,
    });
    const r = await resolveInboundEntity(db, { ...reply, sender: 'anyone@example.com' });
    expect(r.resolved_by).toBe('thread');
    expect(r.related_entity_id).toBe('lead-elin');
  });
});
