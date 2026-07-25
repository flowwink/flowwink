import { usePlatformFormat } from '@/hooks/usePlatformFormat';

/**
 * @deprecated Use `usePlatformFormat()` from `@/hooks/usePlatformFormat`.
 *
 * Kept as a thin delegate so existing call sites (Approvals) keep working
 * without forking a second formatting implementation. It intentionally holds
 * NO formatting logic of its own.
 */
export function useFormatAmount() {
  const { formatCurrency } = usePlatformFormat();
  return (cents: number | null | undefined, currency?: string | null) =>
    formatCurrency(cents, currency);
}
