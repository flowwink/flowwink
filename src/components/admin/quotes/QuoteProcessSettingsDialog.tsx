/**
 * What accepting a quote MEANS — the process dial behind the quote flow.
 *
 * This setting existed before this dialog did: quote-sign reads it server-side
 * (invoice mode auto-creates a draft invoice on accept; contract mode does
 * not), and QuoteDetailSheet reorders its actions around it. But it could only
 * be changed by writing site_settings directly — a dial with consequences and
 * no handle. The handle lives here, on the quotes page, because the person
 * wondering why accept did or didn't create an invoice is standing right here.
 */
import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { Receipt, FileSignature } from 'lucide-react';
import {
  useQuoteProcessSettings,
  useUpdateQuoteProcessSettings,
  type QuoteProcessSettings,
} from '@/hooks/useSiteSettings';

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function QuoteProcessSettingsDialog({ open, onOpenChange }: Props) {
  const { data: settings } = useQuoteProcessSettings();
  const update = useUpdateQuoteProcessSettings();
  const [behavior, setBehavior] = useState<QuoteProcessSettings['accept_behavior']>('invoice');

  // Re-seed from stored settings each time the dialog opens — not only on
  // first mount — so a stale draft choice never survives a cancel.
  useEffect(() => {
    if (open && settings) setBehavior(settings.accept_behavior);
  }, [open, settings]);

  const save = () => {
    update.mutate({ ...settings, accept_behavior: behavior } as QuoteProcessSettings, {
      onSuccess: () => onOpenChange(false),
    });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Quote process</DialogTitle>
          <DialogDescription>
            What accepting a quote means for your business. Applies to every
            quote, including ones already sent.
          </DialogDescription>
        </DialogHeader>

        <RadioGroup
          value={behavior}
          onValueChange={(v) => setBehavior(v as QuoteProcessSettings['accept_behavior'])}
          className="gap-3"
        >
          <Label
            htmlFor="qp-invoice"
            className="flex items-start gap-3 rounded-md border p-4 cursor-pointer has-[[data-state=checked]]:border-primary"
          >
            <RadioGroupItem value="invoice" id="qp-invoice" className="mt-0.5" />
            <div className="space-y-1">
              <span className="font-medium flex items-center gap-1.5">
                <Receipt className="h-4 w-4" /> Quote to cash
              </span>
              <p className="text-sm text-muted-foreground font-normal">
                The quote is the final document. Accepting it creates a draft
                invoice and the customer can pay right away. Right for
                straightforward product and one-off sales.
              </p>
            </div>
          </Label>

          <Label
            htmlFor="qp-contract"
            className="flex items-start gap-3 rounded-md border p-4 cursor-pointer has-[[data-state=checked]]:border-primary"
          >
            <RadioGroupItem value="contract" id="qp-contract" className="mt-0.5" />
            <div className="space-y-1">
              <span className="font-medium flex items-center gap-1.5">
                <FileSignature className="h-4 w-4" /> Quote, then contract
              </span>
              <p className="text-sm text-muted-foreground font-normal">
                Accepting expresses intent — no invoice is created. The binding
                step is the agreement signature, and invoicing follows the
                contract. Right for subscriptions, service agreements and
                anything with a term.
              </p>
            </div>
          </Label>
        </RadioGroup>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={save} disabled={update.isPending}>Save</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
