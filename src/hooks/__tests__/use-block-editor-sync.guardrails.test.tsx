// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useBlockEditor } from '@/hooks/useBlockEditor';

/**
 * The frozen-first-paint class (Magnus, 2026-08-18).
 *
 * useBlockEditor froze whatever the FIRST render passed as initialData. Tabs
 * that mount before their query resolves (FooterTab passes defaults, then the
 * saved block arrives) got an editor stuck on defaults: the footer variant
 * selector showed "full" over a saved "minimal", and applying a variant merged
 * the preset over the frozen defaults — so the user's next Save silently
 * reverted their own earlier edits ("Integritetspolicy" → "Privacy Policy").
 *
 * The repair is a prop-sync with an equality guard. Both halves matter:
 * without the sync, async parents feed stale editors; without the guard, the
 * editor's own onChange round-trips through the parent and resets state on
 * every keystroke.
 */
type Data = { label: string; variant: string };

describe('useBlockEditor prop sync', () => {
  it('adopts new parent content that arrives after mount (async query)', () => {
    const { result, rerender } = renderHook(
      ({ initialData }) => useBlockEditor<Data>({ initialData, onChange: () => {} }),
      { initialProps: { initialData: { label: 'Privacy Policy', variant: 'full' } } },
    );
    expect(result.current.data.variant).toBe('full');

    // The query resolves — the parent re-renders with the SAVED block.
    rerender({ initialData: { label: 'Integritetspolicy', variant: 'minimal' } });
    expect(result.current.data.label).toBe('Integritetspolicy');
    expect(result.current.data.variant).toBe('minimal');
  });

  it('does not reset when its own change round-trips through the parent', () => {
    let parentCopy: Data = { label: 'Integritetspolicy', variant: 'minimal' };
    const { result, rerender } = renderHook(
      ({ initialData }) =>
        useBlockEditor<Data>({
          initialData,
          onChange: (d) => {
            parentCopy = d;
          },
        }),
      { initialProps: { initialData: parentCopy } },
    );

    act(() => {
      result.current.updateField('label', 'Sekretess');
    });
    // Parent stores the change and re-renders with a NEW object, same content.
    rerender({ initialData: { ...parentCopy } });
    expect(result.current.data.label).toBe('Sekretess');
  });

  it('a variant-style updateFields merge keeps fields the parent just delivered', () => {
    const { result, rerender } = renderHook(
      ({ initialData }) => useBlockEditor<Data>({ initialData, onChange: () => {} }),
      { initialProps: { initialData: { label: 'Privacy Policy', variant: 'full' } } },
    );
    rerender({ initialData: { label: 'Integritetspolicy', variant: 'minimal' } });

    // The bug's third act: switching variant used to merge over FROZEN
    // defaults, resurrecting "Privacy Policy". After the sync it merges over
    // the delivered content.
    act(() => {
      result.current.updateFields({ variant: 'enterprise' });
    });
    expect(result.current.data.label).toBe('Integritetspolicy');
    expect(result.current.data.variant).toBe('enterprise');
  });
});
