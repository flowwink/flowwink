import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Plus, Trash2 } from 'lucide-react';
import type { StickyScrollBlockData, StickyScrollChapter } from '@/components/public/blocks/StickyScrollBlock';
import { StickyScrollBlock } from '@/components/public/blocks/StickyScrollBlock';

interface Props {
  data: StickyScrollBlockData;
  onChange: (data: StickyScrollBlockData) => void;
  isEditing: boolean;
}

export function StickyScrollBlockEditor({ data, onChange, isEditing }: Props) {
  const chapters = data.chapters ?? [];

  if (!isEditing) return <StickyScrollBlock data={data} />;

  const addChapter = () => {
    const c: StickyScrollChapter = {
      id: `sc-${Date.now()}`,
      title: 'New chapter',
      body: 'Describe this chapter…',
    };
    onChange({ ...data, chapters: [...chapters, c] });
  };
  const updateChapter = (idx: number, patch: Partial<StickyScrollChapter>) => {
    const next = [...chapters];
    next[idx] = { ...next[idx], ...patch };
    onChange({ ...data, chapters: next });
  };
  const removeChapter = (idx: number) => {
    onChange({ ...data, chapters: chapters.filter((_, i) => i !== idx) });
  };

  return (
    <div className="space-y-6 p-4">
      <div className="grid gap-3 md:grid-cols-2">
        <div className="space-y-2">
          <Label>Eyebrow</Label>
          <Input value={data.eyebrow || ''} onChange={(e) => onChange({ ...data, eyebrow: e.target.value })} />
        </div>
        <div className="space-y-2">
          <Label>Visual side</Label>
          <Select value={data.visualSide || 'right'} onValueChange={(v) => onChange({ ...data, visualSide: v as 'left' | 'right' })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="right">Right</SelectItem>
              <SelectItem value="left">Left</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Title</Label>
          <Input value={data.title || ''} onChange={(e) => onChange({ ...data, title: e.target.value })} />
        </div>
        <div className="space-y-2 md:col-span-2">
          <Label>Subtitle</Label>
          <Textarea rows={2} value={data.subtitle || ''} onChange={(e) => onChange({ ...data, subtitle: e.target.value })} />
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <Label className="text-sm">Chapters ({chapters.length})</Label>
          <Button variant="outline" size="sm" onClick={addChapter}>
            <Plus className="h-3.5 w-3.5 mr-1" /> Add chapter
          </Button>
        </div>
        {chapters.map((chapter, idx) => (
          <div key={chapter.id} className="rounded-lg border border-border/60 p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-muted-foreground">Chapter {idx + 1}</span>
              <Button variant="ghost" size="sm" onClick={() => removeChapter(idx)}>
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
            <Input placeholder="Eyebrow (optional)" value={chapter.eyebrow || ''} onChange={(e) => updateChapter(idx, { eyebrow: e.target.value })} />
            <Input placeholder="Title" value={chapter.title} onChange={(e) => updateChapter(idx, { title: e.target.value })} />
            <Textarea rows={3} placeholder="Body" value={chapter.body} onChange={(e) => updateChapter(idx, { body: e.target.value })} />
            <Input placeholder="Image URL" value={chapter.image || ''} onChange={(e) => updateChapter(idx, { image: e.target.value })} />
          </div>
        ))}
      </div>
    </div>
  );
}
