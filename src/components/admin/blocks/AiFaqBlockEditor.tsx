import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { Plus, Trash2 } from 'lucide-react';
import type { AiFaqBlockData, AiFaqItem } from '@/components/public/blocks/AiFaqBlock';
import { AiFaqBlock } from '@/components/public/blocks/AiFaqBlock';

interface Props {
  data: AiFaqBlockData;
  onChange: (data: AiFaqBlockData) => void;
  isEditing: boolean;
}

export function AiFaqBlockEditor({ data, onChange, isEditing }: Props) {
  const items = data.items ?? [];
  if (!isEditing) return <AiFaqBlock data={data} />;

  const add = () => {
    const item: AiFaqItem = { id: `faq-${Date.now()}`, question: 'New question?', answer: 'Answer here…' };
    onChange({ ...data, items: [...items, item] });
  };
  const update = (idx: number, patch: Partial<AiFaqItem>) => {
    const next = [...items];
    next[idx] = { ...next[idx], ...patch };
    onChange({ ...data, items: next });
  };
  const remove = (idx: number) => onChange({ ...data, items: items.filter((_, i) => i !== idx) });

  return (
    <div className="space-y-6 p-4">
      <div className="grid gap-3 md:grid-cols-2">
        <div className="space-y-2">
          <Label>Eyebrow</Label>
          <Input value={data.eyebrow || ''} onChange={(e) => onChange({ ...data, eyebrow: e.target.value })} />
        </div>
        <div className="space-y-2">
          <Label>Ask AI button label</Label>
          <Input value={data.askAiLabel || ''} onChange={(e) => onChange({ ...data, askAiLabel: e.target.value })} placeholder="Ask AI" />
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Title</Label>
          <Input value={data.title || ''} onChange={(e) => onChange({ ...data, title: e.target.value })} />
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Subtitle</Label>
          <Textarea rows={2} value={data.subtitle || ''} onChange={(e) => onChange({ ...data, subtitle: e.target.value })} />
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Search placeholder</Label>
          <Input value={data.searchPlaceholder || ''} onChange={(e) => onChange({ ...data, searchPlaceholder: e.target.value })} />
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <Label className="text-sm">FAQ items ({items.length})</Label>
          <Button variant="outline" size="sm" onClick={add}>
            <Plus className="h-3.5 w-3.5 mr-1" /> Add question
          </Button>
        </div>
        {items.map((item, idx) => (
          <div key={item.id} className="rounded-lg border border-border/60 p-4 space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-muted-foreground">Q{idx + 1}</span>
              <Button variant="ghost" size="sm" onClick={() => remove(idx)}>
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
            <Input placeholder="Question" value={item.question} onChange={(e) => update(idx, { question: e.target.value })} />
            <Textarea rows={3} placeholder="Answer" value={item.answer} onChange={(e) => update(idx, { answer: e.target.value })} />
          </div>
        ))}
      </div>

      <p className="text-xs text-muted-foreground">
        The Ask AI button routes the visitor's question through <code>chat-completion</code>, seeded with the FAQ above as grounding context.
      </p>
    </div>
  );
}
