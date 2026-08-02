import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

/**
 * URL-driven tab state for admin pages.
 *
 * Process steps live on different pages/tabs (order → pick & pack, PO →
 * receiving → vendor invoice). Without the tab in the URL you cannot deep-link
 * the next step of a process, so every hand-off becomes "go to page X, then
 * find tab Y". This keeps the selected tab shareable and back-button friendly.
 */
export function useTabParam(
  defaultTab: string,
  param = 'tab',
): [string, (next: string) => void] {
  const [searchParams, setSearchParams] = useSearchParams();
  const tab = searchParams.get(param) ?? defaultTab;

  const setTab = useCallback(
    (next: string) => {
      const params = new URLSearchParams(searchParams);
      if (next === defaultTab) params.delete(param);
      else params.set(param, next);
      setSearchParams(params, { replace: true });
    },
    [searchParams, setSearchParams, defaultTab, param],
  );

  return [tab, setTab];
}
