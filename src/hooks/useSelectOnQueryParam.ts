import { useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';

/**
 * Deep-link helper: reads an id from a query param (e.g. /admin/invoices?invoice=…)
 * and hands it to a selection setter so the matching record opens directly.
 * The param is removed afterwards so a refresh doesn't re-open it.
 *
 * `ready` lets list pages wait for their data before resolving the id
 * (e.g. OrdersPage selects a full row object, not just an id).
 */
export function useSelectOnQueryParam(
  param: string,
  select: (id: string) => void,
  ready = true,
): void {
  const [searchParams, setSearchParams] = useSearchParams();
  useEffect(() => {
    const id = searchParams.get(param);
    if (!id || !ready) return;
    select(id);
    const next = new URLSearchParams(searchParams);
    next.delete(param);
    setSearchParams(next, { replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams, ready]);
}
