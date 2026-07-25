import { useMemo } from 'react';
import { usePlatformLocaleSettings, type PlatformLocaleSettings } from '@/hooks/useSiteSettings';

/**
 * Platform-level formatting hook — the single source of truth for how money,
 * dates and numbers are rendered in the UI.
 *
 * Rules (deliberate, do not "improve" these away):
 *  - Locale controls FORMAT, currency controls the SYMBOL. Currency is never
 *    derived from the locale. `formatCurrency(1900, 'USD')` under sv-SE gives
 *    Swedish grouping with a USD symbol.
 *  - This hook FORMATS, it never CONVERTS. No FX anywhere in here — conversion
 *    is an explicit, rate-stamped accounting operation.
 *  - Minor units are resolved per currency via Intl (JPY 0, SEK/EUR/USD 2,
 *    KWD 3). No hardcoded ÷100.
 *  - `formatDate` is for date-only values and applies NO timezone shifting.
 *    `formatDateTime` applies the platform timezone to real timestamps.
 *
 * Presentation currency (this hook) is NOT the accounting/functional currency.
 * Keep them separate.
 */

/** Digits of the currency's minor unit, per Intl. Falls back to 2. */
function minorUnitDigits(locale: string, currency: string): number {
  try {
    const opts = new Intl.NumberFormat(locale, { style: 'currency', currency }).resolvedOptions();
    return opts.maximumFractionDigits ?? 2;
  } catch {
    return 2;
  }
}

export interface PlatformFormat {
  settings: PlatformLocaleSettings;
  /**
   * Amount is given in MINOR units (öre/cents/…) of `currency`.
   *
   * `options` is a narrow escape hatch for presentation-only tweaks — chiefly
   * `maximumFractionDigits: 0` for whole-unit displays (salary bands, KPI
   * tiles) that would otherwise gain a misleading ",00". It must never be used
   * to change the currency or the locale.
   */
  formatCurrency: (
    amountMinorUnits: number | null | undefined,
    currency?: string | null,
    options?: Omit<Intl.NumberFormatOptions, 'style' | 'currency'>,
  ) => string;
  /** Date-only value ("2026-07-08" or a Date) — never timezone-shifted. */
  formatDate: (dateOnly: string | Date | null | undefined) => string;
  /** Real timestamp — rendered in the platform timezone. */
  formatDateTime: (timestamp: string | Date | null | undefined) => string;
  formatNumber: (n: number | null | undefined, options?: Intl.NumberFormatOptions) => string;
}

export function usePlatformFormat(): PlatformFormat {
  const { data: settings } = usePlatformLocaleSettings();
  const s = settings ?? {
    default_locale: 'sv-SE',
    default_currency: 'SEK',
    default_timezone: 'Europe/Stockholm',
  };

  return useMemo<PlatformFormat>(() => {
    const locale = s.default_locale;
    const tz = s.default_timezone;

    const formatCurrency = (
      amountMinorUnits: number | null | undefined,
      currency?: string | null,
      options?: Omit<Intl.NumberFormatOptions, 'style' | 'currency'>,
    ) => {
      if (amountMinorUnits == null || Number.isNaN(amountMinorUnits)) return '—';
      const cur = (currency || s.default_currency).toUpperCase();
      // Scaling ALWAYS uses the currency's true minor-unit digits — `options`
      // may change how the value is displayed, never how it is scaled.
      const digits = minorUnitDigits(locale, cur);
      const major = amountMinorUnits / Math.pow(10, digits);
      try {
        return new Intl.NumberFormat(locale, {
          ...options,
          style: 'currency',
          currency: cur,
        }).format(major);
      } catch {
        return `${major.toFixed(digits)} ${cur}`;
      }
    };

    const formatDate = (dateOnly: string | Date | null | undefined) => {
      if (!dateOnly) return '—';
      // Date-only must never shift across a timezone boundary: parse the
      // Y-M-D parts and render them literally (UTC anchor + UTC formatting).
      let y: number, m: number, d: number;
      if (typeof dateOnly === 'string') {
        const match = dateOnly.match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (!match) return dateOnly;
        [, y, m, d] = match.map(Number) as unknown as [unknown, number, number, number];
      } else {
        y = dateOnly.getFullYear();
        m = dateOnly.getMonth() + 1;
        d = dateOnly.getDate();
      }
      const anchor = new Date(Date.UTC(y, m - 1, d));
      try {
        return new Intl.DateTimeFormat(locale, {
          year: 'numeric',
          month: 'short',
          day: '2-digit',
          timeZone: 'UTC',
        }).format(anchor);
      } catch {
        return anchor.toISOString().slice(0, 10);
      }
    };

    const formatDateTime = (timestamp: string | Date | null | undefined) => {
      if (!timestamp) return '—';
      const dt = typeof timestamp === 'string' ? new Date(timestamp) : timestamp;
      if (Number.isNaN(dt.getTime())) return '—';
      try {
        return new Intl.DateTimeFormat(locale, {
          year: 'numeric',
          month: 'short',
          day: '2-digit',
          hour: '2-digit',
          minute: '2-digit',
          timeZone: tz,
        }).format(dt);
      } catch {
        return dt.toISOString();
      }
    };

    const formatNumber = (n: number | null | undefined, options?: Intl.NumberFormatOptions) => {
      if (n == null || Number.isNaN(n)) return '—';
      try {
        return new Intl.NumberFormat(locale, options).format(n);
      } catch {
        return String(n);
      }
    };

    return { settings: s, formatCurrency, formatDate, formatDateTime, formatNumber };
  }, [s.default_locale, s.default_currency, s.default_timezone]);
}
