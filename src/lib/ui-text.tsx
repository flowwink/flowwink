import { createContext, useContext, useMemo, type ReactNode } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';

/**
 * Visitor-facing UI strings that are not page content.
 *
 * Block content has always been editable — a title, a button label, a
 * thank-you. But the chrome around it was not: "Send message", "No results
 * found", "Back to homepage", "Previous page". A site launched in Swedish
 * translated everything an editor could reach and still said "Your message"
 * above the chat box. We found that class three times in one evening (cookie
 * banner, newsletter placeholders, the KB's "Can't find the answer?") before
 * measuring it: 120 hardcoded strings across 45 public files.
 *
 * Hardcoding Swedish would only move the problem to the next language, so the
 * strings become data, following the localization law — language is a pack the
 * engine reads, never a branch the engine takes.
 *
 * `site_settings.ui_text` holds a flat `{ key: translation }` map. Anything
 * absent falls back to the English written at the call site, so an instance
 * that never sets the key behaves exactly as it does today (Law 4: degrade,
 * never gate). An agent can translate a whole site through
 * `manage_site_settings` without a deploy.
 */

type UiTextMap = Record<string, string>;

const UiTextContext = createContext<UiTextMap>({});

export function UiTextProvider({ children }: { children: ReactNode }) {
  const { data } = useQuery({
    queryKey: ['site-settings', 'ui_text'],
    queryFn: async () => {
      const { data } = await supabase
        .from('site_settings').select('value').eq('key', 'ui_text').maybeSingle();
      return (data?.value as UiTextMap) || {};
    },
    staleTime: 10 * 60 * 1000,
    // A missing table/row must never blank the UI — the fallbacks carry it.
    retry: false,
  });

  const map = data ?? {};
  return <UiTextContext.Provider value={map}>{children}</UiTextContext.Provider>;
}

/**
 * `const t = useUiText(); t('chat.send', 'Send message')`
 *
 * The English fallback is required and lives at the call site, so the code
 * stays readable and a missing pack is invisible rather than broken.
 */
export function useUiText() {
  const map = useContext(UiTextContext);
  return useMemo(
    () => (key: string, fallback: string) => map[key] ?? fallback,
    [map],
  );
}
