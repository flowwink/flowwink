/**
 * The income statement, and the account that must not appear on it.
 * ──────────────────────────────────────────────────────────────────
 *
 * A double-entry ledger books the year's result twice on purpose. Once as the
 * difference between income and expense, and once — at closing — as an entry
 * that moves that difference into equity: debit the result-carrying account,
 * credit "Årets resultat" in equity. The carrier is a P&L-side account, so a
 * report that sums every P&L account counts the result a second time with the
 * opposite sign and lands on exactly zero. Every time, for every company, for
 * every closed year.
 *
 * Found on LiteIT 2024 (2026-08-10): income 26 172,11 − expenses 26 172,11,
 * net 0. The real result was +19 537,11, and the årsredovisning agreed. The
 * failure is silent and it is total — the number is not off, it is gone — and
 * it looks like an ordinary balanced report, which is why nobody spots it.
 *
 * WHICH account carries the result is not something this file may know. In
 * BAS 2024 it is 8999; a company arriving with its own chart may use another;
 * an IFRS chart closes P&L straight to retained earnings and has no carrier at
 * all, so "there is none" is a correct answer, not a missing configuration.
 * Same reasoning as account_tax_boxes: the classification is a property of the
 * chart, held in data, and the engine only asks.
 *
 * Tax is split out for the same reason a statutory annual report splits it out:
 * "resultat före skatt" is a line a reader compares against, and it cannot be
 * recovered from a lump sum of expenses.
 */

/** One account's aggregated position over the report period. */
export interface StatementAccount {
  account_code: string;
  account_name: string;
  account_type: string;
  debit_total: number;
  credit_total: number;
  /** Signed in the account's own normal direction (income positive = credit). */
  balance: number;
}

/**
 * Which accounts play a special part in the statement, read from the instance's
 * own chart. Empty sets are legitimate — see the IFRS case above.
 */
export interface StatementClassification {
  /** Accounts the closing entry books the result onto. Excluded from the statement. */
  resultCarrierAccounts: string[];
  /** Accounts forming the "Skatt på årets resultat" line. */
  taxAccounts: string[];
  /** Where the mapping came from — a report must not hide its own basis. */
  source: 'account_statement_sections' | 'account_roles' | 'unmapped';
}

export const EMPTY_CLASSIFICATION: StatementClassification = {
  resultCarrierAccounts: [],
  taxAccounts: [],
  source: 'unmapped',
};

const isIncome = (a: StatementAccount) =>
  a.account_type === 'revenue' || a.account_type === 'income';
const isExpense = (a: StatementAccount) => a.account_type === 'expense';

/**
 * How much of the result the closing entry has already moved into equity,
 * signed the way a profit is: positive means a profit was carried across.
 *
 * Read from the raw debit/credit totals rather than `balance`, because the
 * carrier's sign convention depends on how the chart types it, and this
 * quantity has to mean the same thing whichever way that goes.
 */
export function closedToEquityCents(
  balances: StatementAccount[],
  classification: StatementClassification,
): number {
  const carriers = new Set(classification.resultCarrierAccounts);
  if (carriers.size === 0) return 0;
  return balances
    .filter((b) => carriers.has(b.account_code))
    .reduce((sum, b) => sum + (Number(b.debit_total) || 0) - (Number(b.credit_total) || 0), 0);
}

export interface IncomeStatement {
  income: StatementAccount[];
  expenses: StatementAccount[];
  tax: StatementAccount[];
  total_income_cents: number;
  /** Operating and financial expenses. Excludes tax and the result carrier. */
  total_expenses_cents: number;
  tax_cents: number;
  result_before_tax_cents: number;
  net_result_cents: number;
  profitable: boolean;
  result_carrier: {
    accounts: string[];
    source: StatementClassification['source'];
    closed_to_equity_cents: number;
    /**
     * After a closing entry the carrier must hold exactly the net result. When
     * it does not, either the closing entry is partial or an account is
     * classified wrongly — and the report says so instead of averaging it away.
     */
    agrees_with_net_result: boolean;
    note?: string;
  };
}

export function buildIncomeStatement(
  balances: StatementAccount[],
  classification: StatementClassification,
): IncomeStatement {
  const carriers = new Set(classification.resultCarrierAccounts);
  const taxCodes = new Set(classification.taxAccounts);

  const onStatement = balances.filter((b) => !carriers.has(b.account_code) && b.balance !== 0);
  const income = onStatement.filter(isIncome);
  const tax = onStatement.filter((b) => isExpense(b) && taxCodes.has(b.account_code));
  const expenses = onStatement.filter((b) => isExpense(b) && !taxCodes.has(b.account_code));

  const sum = (rows: StatementAccount[]) => rows.reduce((s, r) => s + r.balance, 0);
  const totalIncome = sum(income);
  const totalExpenses = sum(expenses);
  const taxCents = sum(tax);
  const resultBeforeTax = totalIncome - totalExpenses;
  const netResult = resultBeforeTax - taxCents;

  const closed = closedToEquityCents(balances, classification);

  return {
    income,
    expenses,
    tax,
    total_income_cents: totalIncome,
    total_expenses_cents: totalExpenses,
    tax_cents: taxCents,
    result_before_tax_cents: resultBeforeTax,
    net_result_cents: netResult,
    profitable: netResult > 0,
    result_carrier: {
      accounts: classification.resultCarrierAccounts,
      source: classification.source,
      closed_to_equity_cents: closed,
      agrees_with_net_result: closed === 0 || closed === netResult,
      ...(classification.source === 'unmapped'
        ? {
            note:
              'No result-carrying account is mapped for this accounting locale. If this ' +
              'chart closes the year onto a P&L account, that account is being counted as ' +
              'an ordinary line and the net result will read as zero — map it (role ' +
              'year_result / section year_result). Charts that close straight to retained ' +
              'earnings correctly have none.',
          }
        : {}),
    },
  };
}

/**
 * The part of the period's result that is NOT yet in equity.
 *
 * The balance sheet needs the result as a plug so it balances mid-year, and
 * that plug must shrink to nothing as the closing entry moves the result onto
 * an equity account — otherwise the result is counted in equity twice.
 *
 * The old code got the same answer by including the carrier in the P&L sum,
 * so the plug went to zero because the P&L itself did. That was right by
 * accident and only while the P&L was wrong.
 */
export function unclosedResultCents(
  balances: StatementAccount[],
  classification: StatementClassification,
): number {
  const statement = buildIncomeStatement(balances, classification);
  return statement.net_result_cents - statement.result_carrier.closed_to_equity_cents;
}

/** Minimal shape of the Supabase client this loader needs. */
interface QueryClient {
  from(table: string): any;
}

/** Fallback when site_settings carries no accounting_locale — mirrors account_for(). */
export const DEFAULT_ACCOUNTING_LOCALE = 'se-bas2024';

export async function resolveAccountingLocale(supabase: QueryClient): Promise<string> {
  const { data } = await supabase
    .from('site_settings')
    .select('value')
    .eq('key', 'accounting_locale')
    .maybeSingle();
  const raw = (data as any)?.value;
  const fromString = typeof raw === 'string' ? raw : null;
  const fromObject = raw && typeof raw === 'object' ? (raw as any).id : null;
  return fromString || fromObject || DEFAULT_ACCOUNTING_LOCALE;
}

/**
 * Read the statement classification for this instance.
 *
 * Two sources, in order, and the response reports which one answered:
 *   1. account_statement_sections — the map proper; holds every account in a
 *      section, so a chart with more than one result account is expressible.
 *   2. account_roles.year_result — the single posting target the closing entry
 *      uses. Older instances have the role before they have the table, and an
 *      instance mid-deploy should keep reporting a real result rather than
 *      going back to reporting zero.
 */
export async function loadStatementClassification(
  supabase: QueryClient,
  localeOverride?: string,
): Promise<StatementClassification & { locale: string }> {
  const locale = localeOverride || (await resolveAccountingLocale(supabase));

  const { data: sections, error: sectionsErr } = await supabase
    .from('account_statement_sections')
    .select('section, account_code')
    .eq('locale', locale);

  if (!sectionsErr && sections && sections.length > 0) {
    const bySection = (name: string) =>
      (sections as any[]).filter((r) => r.section === name).map((r) => String(r.account_code));
    return {
      locale,
      resultCarrierAccounts: bySection('year_result'),
      taxAccounts: bySection('income_tax'),
      source: 'account_statement_sections',
    };
  }

  const { data: role } = await supabase
    .from('account_roles')
    .select('account_code')
    .eq('locale', locale)
    .eq('role', 'year_result')
    .maybeSingle();

  const carrier = (role as any)?.account_code ? [String((role as any).account_code)] : [];
  return {
    locale,
    resultCarrierAccounts: carrier,
    taxAccounts: [],
    source: carrier.length > 0 ? 'account_roles' : 'unmapped',
  };
}
