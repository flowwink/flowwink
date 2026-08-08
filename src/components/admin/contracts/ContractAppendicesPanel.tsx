/**
 * Appendices for one agreement.
 *
 * An APPENDIX is part of the agreement — the body says "enligt Bilaga 1", it
 * carries a precedence order, and the customer sees it (and signs it) on the
 * public page. That is a different thing from a DOCUMENT filed against the
 * contract (correspondence, the countersigned PDF), which lives in the
 * Documents tab. Keeping them apart is the point: only appendices travel to
 * the counterparty as part of what is being signed.
 *
 * Two kinds, one numbered list:
 *   from a template — renders an appendix contract_template into the agreement
 *   a file          — a spec, a drawing, a price list
 */
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Trash2, Plus, Paperclip, FileText, Loader2 } from 'lucide-react';
import { toast } from 'sonner';

interface Appendix {
  id: string;
  label: string | null;
  title: string | null;
  kind: 'file' | 'document';
  sort_order: number;
  file_name: string | null;
  file_url: string | null;
  has_body: boolean;
}

const rpc = (args: Record<string, unknown>) =>
  supabase.rpc('manage_contract_appendix' as never, args as never);

export function ContractAppendicesPanel({ contractId }: { contractId: string }) {
  const qc = useQueryClient();
  const [mode, setMode] = useState<'none' | 'template' | 'file'>('none');
  const [templateId, setTemplateId] = useState('');
  const [label, setLabel] = useState('');
  const [title, setTitle] = useState('');
  const [fileUrl, setFileUrl] = useState('');
  const [fileName, setFileName] = useState('');

  const { data: appendices = [], isLoading } = useQuery({
    queryKey: ['contract-appendices', contractId],
    queryFn: async () => {
      const { data, error } = await rpc({ p_action: 'list', p_contract_id: contractId });
      if (error) throw error;
      return ((data as { appendices?: Appendix[] })?.appendices ?? []) as Appendix[];
    },
  });

  const { data: templates = [] } = useQuery({
    queryKey: ['contract-templates-for-appendix'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('contract_templates')
        .select('id, name')
        .eq('is_active', true)
        .order('name');
      if (error) throw error;
      return (data ?? []) as { id: string; name: string }[];
    },
  });

  const reset = () => {
    setMode('none'); setTemplateId(''); setLabel(''); setTitle(''); setFileUrl(''); setFileName('');
  };

  const add = useMutation({
    mutationFn: async () => {
      const args: Record<string, unknown> = {
        p_action: 'create',
        p_contract_id: contractId,
        p_label: label.trim() || null,
        p_title: title.trim() || null,
      };
      if (mode === 'template') args.p_template = templateId;
      else { args.p_file_url = fileUrl.trim(); args.p_file_name = fileName.trim() || null; }
      const { error } = await rpc(args);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Appendix added');
      reset();
      qc.invalidateQueries({ queryKey: ['contract-appendices', contractId] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const remove = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await rpc({ p_action: 'delete', p_appendix_id: id });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success('Appendix removed');
      qc.invalidateQueries({ queryKey: ['contract-appendices', contractId] });
    },
    onError: (e: Error) => toast.error(e.message),
  });

  const canSubmit = mode === 'template' ? !!templateId : fileUrl.trim().length > 0;

  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">Appendices</CardTitle>
        <p className="text-sm text-muted-foreground">
          Parts of the agreement the body references (&ldquo;enligt Bilaga 1&rdquo;). The
          counterparty sees these on the signing page and they are covered by the signature.
        </p>
      </CardHeader>
      <CardContent className="space-y-4">
        {isLoading ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : appendices.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No appendices yet. If the agreement text mentions a Bilaga, add it here — otherwise
            the customer signs a reference to something that isn&rsquo;t there.
          </p>
        ) : (
          <ul className="space-y-2">
            {appendices.map((a) => (
              <li key={a.id} className="flex items-center gap-3 rounded-md border p-3">
                {a.kind === 'file'
                  ? <Paperclip className="h-4 w-4 text-muted-foreground shrink-0" />
                  : <FileText className="h-4 w-4 text-muted-foreground shrink-0" />}
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium truncate">
                    {a.label}{a.title ? ` — ${a.title}` : ''}
                  </p>
                  {a.kind === 'file' && a.file_url && (
                    <a href={a.file_url} target="_blank" rel="noreferrer noopener"
                       className="text-xs text-primary underline">
                      {a.file_name || a.file_url}
                    </a>
                  )}
                </div>
                <Badge variant="secondary" className="shrink-0">
                  {a.kind === 'file' ? 'File' : 'Document'}
                </Badge>
                <Button variant="ghost" size="icon" onClick={() => remove.mutate(a.id)}>
                  <Trash2 className="h-4 w-4" />
                </Button>
              </li>
            ))}
          </ul>
        )}

        {mode === 'none' ? (
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => setMode('template')}>
              <Plus className="h-4 w-4 mr-1" /> From template
            </Button>
            <Button variant="outline" size="sm" onClick={() => setMode('file')}>
              <Paperclip className="h-4 w-4 mr-1" /> Attach file
            </Button>
          </div>
        ) : (
          <div className="space-y-3 rounded-md border p-4">
            {mode === 'template' ? (
              <div className="space-y-2">
                <Label>Template</Label>
                <Select value={templateId} onValueChange={setTemplateId}>
                  <SelectTrigger><SelectValue placeholder="Pick an appendix template…" /></SelectTrigger>
                  <SelectContent>
                    {templates.map((t) => (
                      <SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="ap-url">File URL</Label>
                  <Input id="ap-url" value={fileUrl} onChange={(e) => setFileUrl(e.target.value)}
                         placeholder="https://…" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="ap-name">File name</Label>
                  <Input id="ap-name" value={fileName} onChange={(e) => setFileName(e.target.value)}
                         placeholder="spec.pdf" />
                </div>
              </div>
            )}
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="space-y-2">
                <Label htmlFor="ap-label">Label</Label>
                <Input id="ap-label" value={label} onChange={(e) => setLabel(e.target.value)}
                       placeholder="Bilaga 1 (auto if empty)" />
                <p className="text-xs text-muted-foreground">Must match what the agreement text says.</p>
              </div>
              <div className="space-y-2">
                <Label htmlFor="ap-title">Title</Label>
                <Input id="ap-title" value={title} onChange={(e) => setTitle(e.target.value)}
                       placeholder="Tjänstebeskrivning" />
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="outline" size="sm" onClick={reset}>Cancel</Button>
              <Button size="sm" disabled={!canSubmit || add.isPending} onClick={() => add.mutate()}>
                {add.isPending && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
                Add appendix
              </Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
