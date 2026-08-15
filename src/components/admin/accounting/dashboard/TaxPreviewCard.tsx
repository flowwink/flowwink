import { DashCard, BigFigure, Subline, QuietEmpty, useFmtSek } from './_shared';
import { useIncomeStatementYTD } from './ResultCard';

const CORPORATE_TAX_RATE = 0.206;

export function TaxPreviewCard() {
  const { data, isLoading, isError } = useIncomeStatementYTD();
  const fmtSek = useFmtSek();

  if (isLoading) {
    return (
      <DashCard label="Estimated corporate tax">
        <QuietEmpty>Loading…</QuietEmpty>
      </DashCard>
    );
  }

  if (isError || !data) {
    return (
      <DashCard label="Estimated corporate tax">
        <QuietEmpty>No data yet.</QuietEmpty>
      </DashCard>
    );
  }

  // Corporate tax is levied on the result BEFORE tax. Once a closing entry
  // exists, net_result_cents is already net of the tax booked on 8910 and using
  // it here would tax the after-tax figure. Older report payloads (an instance
  // whose agent-execute has not been redeployed) carry no result_before_tax_cents.
  const result = data.result_before_tax_cents ?? data.net_result_cents;
  if (result <= 0) {
    return (
      <DashCard label="Estimated corporate tax">
        <BigFigure value={fmtSek(0)} />
        <Subline>No tax on current result · Preliminary — running estimate</Subline>
      </DashCard>
    );
  }

  const taxCents = Math.round(result * CORPORATE_TAX_RATE);
  return (
    <DashCard label="Estimated corporate tax (20.6%)">
      <BigFigure value={fmtSek(taxCents)} />
      <Subline>Preliminary — running estimate</Subline>
    </DashCard>
  );
}
