import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { Plus, Trash2 } from 'lucide-react';
import type {
  PricingCalculatorBlockData,
  PricingCalculatorVariable,
} from '@/components/public/blocks/PricingCalculatorBlock';
import { PricingCalculatorBlock } from '@/components/public/blocks/PricingCalculatorBlock';

interface Props {
  data: PricingCalculatorBlockData;
  onChange: (data: PricingCalculatorBlockData) => void;
  isEditing: boolean;
}

export function PricingCalculatorBlockEditor({ data, onChange, isEditing }: Props) {
  const variables = data.variables ?? [];
  if (!isEditing) return <PricingCalculatorBlock data={data} />;

  const add = () => {
    const v: PricingCalculatorVariable = {
      id: `pc-${Date.now()}`,
      label: 'Users',
      min: 1,
      max: 100,
      step: 1,
      unit: 'users',
      unitPrice: 10,
      defaultValue: 10,
    };
    onChange({ ...data, variables: [...variables, v] });
  };
  const update = (idx: number, patch: Partial<PricingCalculatorVariable>) => {
    const next = [...variables];
    next[idx] = { ...next[idx], ...patch };
    onChange({ ...data, variables: next });
  };
  const remove = (idx: number) =>
    onChange({ ...data, variables: variables.filter((_, i) => i !== idx) });

  const num = (v: string) => (v === '' ? 0 : Number(v));

  return (
    <div className="space-y-6 p-4">
      <div className="grid gap-3 md:grid-cols-2">
        <div className="space-y-2">
          <Label>Eyebrow</Label>
          <Input value={data.eyebrow || ''} onChange={(e) => onChange({ ...data, eyebrow: e.target.value })} />
        </div>
        <div className="space-y-2">
          <Label>Currency symbol</Label>
          <Input value={data.currencySymbol || ''} onChange={(e) => onChange({ ...data, currencySymbol: e.target.value })} placeholder="$" />
        </div>
        <div className="space-y-2">
          <Label>Base price</Label>
          <Input type="number" value={data.basePrice ?? 0} onChange={(e) => onChange({ ...data, basePrice: num(e.target.value) })} />
        </div>
        <div className="space-y-2">
          <Label>Billing label</Label>
          <Input value={data.billingLabel || ''} onChange={(e) => onChange({ ...data, billingLabel: e.target.value })} placeholder="per month" />
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Title</Label>
          <Input value={data.title || ''} onChange={(e) => onChange({ ...data, title: e.target.value })} />
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Subtitle</Label>
          <Textarea rows={2} value={data.subtitle || ''} onChange={(e) => onChange({ ...data, subtitle: e.target.value })} />
        </div>
        <div className="space-y-2">
          <Label>CTA text</Label>
          <Input value={data.primaryButton?.text || ''} onChange={(e) => onChange({ ...data, primaryButton: { text: e.target.value, url: data.primaryButton?.url || '' } })} />
        </div>
        <div className="space-y-2">
          <Label>CTA URL</Label>
          <Input value={data.primaryButton?.url || ''} onChange={(e) => onChange({ ...data, primaryButton: { text: data.primaryButton?.text || '', url: e.target.value } })} />
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Secondary note</Label>
          <Input value={data.secondaryNote || ''} onChange={(e) => onChange({ ...data, secondaryNote: e.target.value })} placeholder="Volume discount at 100+ users" />
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <Label className="text-sm">Variables ({variables.length})</Label>
          <Button variant="outline" size="sm" onClick={add}>
            <Plus className="h-3.5 w-3.5 mr-1" /> Add variable
          </Button>
        </div>
        {variables.map((v, idx) => (
          <div key={v.id} className="rounded-lg border border-border/60 p-4 space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-muted-foreground">Variable {idx + 1}</span>
              <Button variant="ghost" size="sm" onClick={() => remove(idx)}>
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
            <div className="grid gap-2 md:grid-cols-2">
              <Input placeholder="Label (e.g. Users)" value={v.label} onChange={(e) => update(idx, { label: e.target.value })} />
              <Input placeholder="Unit (e.g. users)" value={v.unit || ''} onChange={(e) => update(idx, { unit: e.target.value })} />
              <Input placeholder="Min" type="number" value={v.min} onChange={(e) => update(idx, { min: num(e.target.value) })} />
              <Input placeholder="Max" type="number" value={v.max} onChange={(e) => update(idx, { max: num(e.target.value) })} />
              <Input placeholder="Step" type="number" value={v.step ?? 1} onChange={(e) => update(idx, { step: num(e.target.value) })} />
              <Input placeholder="Default" type="number" value={v.defaultValue ?? v.min} onChange={(e) => update(idx, { defaultValue: num(e.target.value) })} />
              <Input placeholder="Unit price" type="number" step="0.01" value={v.unitPrice} onChange={(e) => update(idx, { unitPrice: num(e.target.value) })} className="md:col-span-2" />
              <Textarea placeholder="Description (optional)" rows={2} value={v.description || ''} onChange={(e) => update(idx, { description: e.target.value })} className="md:col-span-2" />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
