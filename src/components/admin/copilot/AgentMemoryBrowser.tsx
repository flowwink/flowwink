/**
 * Agent memory browser — lists rows from `agent_memory` grouped by category,
 * with edit / delete / add. Keeps the surface small; deep edits happen via
 * FlowPilot skills or the DB directly.
 */
import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogTrigger,
} from '@/components/ui/dialog';
import { Brain, Plus, Trash2, Pencil, Loader2 } from 'lucide-react';
import { toast } from 'sonner';
import { formatDistanceToNow } from 'date-fns';

type Category = 'context' | 'preference' | 'fact' | 'skill' | 'other';

interface MemoryRow {
  id: string;
  key: string;
  value: unknown;
  category: Category;
  created_at: string;
  updated_at: string;
  expires_at: string | null;
}

const CATEGORIES: Category[] = ['context', 'preference', 'fact', 'skill', 'other'];

export function AgentMemoryBrowser() {
  const qc = useQueryClient();
  const [filter, setFilter] = useState<Category | 'all'>('all');
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<MemoryRow | null>(null);
  const [creating, setCreating] = useState(false);

  const { data: rows, isLoading } = useQuery({
    queryKey: ['agent-memory'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('agent_memory')
        .select('id, key, value, category, created_at, updated_at, expires_at')
        .order('updated_at', { ascending: false })
        .limit(500);
      if (error) throw error;
      return data as unknown as MemoryRow[];
    },
  });

  const filtered = (rows ?? []).filter(r => {
    if (filter !== 'all' && r.category !== filter) return false;
    if (search && !r.key.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const counts = CATEGORIES.reduce<Record<string, number>>((acc, c) => {
    acc[c] = (rows ?? []).filter(r => r.category === c).length;
    return acc;
  }, {});

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this memory entry?')) return;
    const { error } = await supabase.from('agent_memory').delete().eq('id', id);
    if (error) return toast.error(error.message);
    toast.success('Memory entry deleted');
    qc.invalidateQueries({ queryKey: ['agent-memory'] });
  };

  return (
    <Card>
      <CardHeader>
        <div className="flex items-start justify-between gap-4">
          <div>
            <CardTitle className="text-base flex items-center gap-2">
              <Brain className="h-4 w-4 text-primary" />
              Agent memory
            </CardTitle>
            <CardDescription>
              Persistent context FlowPilot uses across sessions. {rows?.length ?? 0} entries.
            </CardDescription>
          </div>
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="h-4 w-4 mr-1.5" /> Add entry
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Button
            size="sm"
            variant={filter === 'all' ? 'default' : 'outline'}
            onClick={() => setFilter('all')}
            className="h-7 text-xs"
          >
            All <Badge variant="secondary" className="ml-1.5 text-[10px]">{rows?.length ?? 0}</Badge>
          </Button>
          {CATEGORIES.map(c => (
            <Button
              key={c}
              size="sm"
              variant={filter === c ? 'default' : 'outline'}
              onClick={() => setFilter(c)}
              className="h-7 text-xs capitalize"
            >
              {c} <Badge variant="secondary" className="ml-1.5 text-[10px]">{counts[c] ?? 0}</Badge>
            </Button>
          ))}
          <Input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search key…"
            className="h-7 text-xs max-w-[200px] ml-auto"
          />
        </div>

        {isLoading ? (
          <div className="text-xs text-muted-foreground py-6 text-center">Loading…</div>
        ) : filtered.length === 0 ? (
          <div className="text-xs text-muted-foreground py-6 text-center">
            No memory entries {filter !== 'all' ? `in "${filter}"` : ''}.
          </div>
        ) : (
          <div className="rounded-md border divide-y">
            {filtered.map(row => (
              <div key={row.id} className="p-3 flex items-start gap-3 hover:bg-muted/40">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <Badge variant="outline" className="text-[10px] capitalize">{row.category}</Badge>
                    <span className="font-mono text-xs truncate">{row.key}</span>
                  </div>
                  <div className="text-xs text-muted-foreground truncate font-mono">
                    {typeof row.value === 'string' ? row.value : JSON.stringify(row.value)}
                  </div>
                  <div className="text-[10px] text-muted-foreground mt-1">
                    Updated {formatDistanceToNow(new Date(row.updated_at), { addSuffix: true })}
                    {row.expires_at && ` · expires ${formatDistanceToNow(new Date(row.expires_at), { addSuffix: true })}`}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setEditing(row)}>
                    <Pencil className="h-3.5 w-3.5" />
                  </Button>
                  <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => handleDelete(row.id)}>
                    <Trash2 className="h-3.5 w-3.5 text-destructive" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>

      <MemoryEditorDialog
        open={!!editing || creating}
        row={editing}
        onOpenChange={o => { if (!o) { setEditing(null); setCreating(false); } }}
        onSaved={() => qc.invalidateQueries({ queryKey: ['agent-memory'] })}
      />
    </Card>
  );
}

function MemoryEditorDialog({
  open, row, onOpenChange, onSaved,
}: {
  open: boolean;
  row: MemoryRow | null;
  onOpenChange: (o: boolean) => void;
  onSaved: () => void;
}) {
  const [key, setKey] = useState('');
  const [category, setCategory] = useState<Category>('context');
  const [valueText, setValueText] = useState('');
  const [saving, setSaving] = useState(false);

  // Reset form when opening
  useState(() => {
    if (open) {
      setKey(row?.key ?? '');
      setCategory(row?.category ?? 'context');
      setValueText(row ? (typeof row.value === 'string' ? row.value : JSON.stringify(row.value, null, 2)) : '');
    }
  });

  // Reset on open change
  if (open && row && key === '' && row.key) {
    setKey(row.key);
    setCategory(row.category);
    setValueText(typeof row.value === 'string' ? row.value : JSON.stringify(row.value, null, 2));
  }

  const handleSave = async () => {
    if (!key.trim()) return toast.error('Key is required');
    let parsedValue: unknown = valueText;
    try {
      parsedValue = JSON.parse(valueText);
    } catch {
      // fall back to raw string
    }
    setSaving(true);
    try {
      if (row) {
        const { error } = await supabase
          .from('agent_memory')
          .update({ key, category, value: parsedValue as never, updated_at: new Date().toISOString() })
          .eq('id', row.id);
        if (error) throw error;
        toast.success('Memory entry updated');
      } else {
        const { error } = await supabase
          .from('agent_memory')
          .insert({ key, category, value: parsedValue as never });
        if (error) throw error;
        toast.success('Memory entry created');
      }
      onSaved();
      onOpenChange(false);
      setKey(''); setValueText(''); setCategory('context');
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={o => { if (!o) { setKey(''); setValueText(''); setCategory('context'); } onOpenChange(o); }}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{row ? 'Edit memory entry' : 'New memory entry'}</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="mem-key" className="text-xs">Key</Label>
            <Input id="mem-key" value={key} onChange={e => setKey(e.target.value)} placeholder="e.g. brand_voice" className="font-mono text-xs" />
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs">Category</Label>
            <Select value={category} onValueChange={v => setCategory(v as Category)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {CATEGORIES.map(c => <SelectItem key={c} value={c} className="capitalize">{c}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="mem-value" className="text-xs">Value (JSON or text)</Label>
            <Textarea
              id="mem-value"
              value={valueText}
              onChange={e => setValueText(e.target.value)}
              rows={8}
              className="font-mono text-xs"
              placeholder='"friendly, concise" or {"tone": "friendly"}'
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving && <Loader2 className="h-3.5 w-3.5 mr-1.5 animate-spin" />} Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
