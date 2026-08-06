/**
 * Public terms page — /villkor
 *
 * The agreement the customer signs is two pages; its substance lives in
 * versioned terms documents referenced by name and date. This page publishes
 * exactly those documents, rendered from the same contract_templates rows the
 * agreements point at — one source, the way a privacy policy is published.
 * Templates appear here only when an operator flips is_public.
 */
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Helmet } from 'react-helmet-async';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { ChevronDown, Download, FileText } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader } from '@/components/ui/card';
import { supabase } from '@/integrations/supabase/client';

interface PublicTerm {
  id: string;
  name: string;
  description: string | null;
  body_markdown: string;
  updated_at: string;
}

export default function PublicTermsPage() {
  const [openId, setOpenId] = useState<string | null>(null);

  const { data: terms = [], isLoading } = useQuery({
    queryKey: ['public-terms'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('get_public_terms' as never);
      if (error) throw error;
      return (data ?? []) as unknown as PublicTerm[];
    },
  });

  const printTerm = (t: PublicTerm) => {
    const el = document.querySelector(`[data-term-body="${t.id}"]`);
    const w = window.open('', '_blank', 'noopener,width=800,height=1000');
    if (!w || !el) return;
    w.document.write(`<!doctype html><html><head><meta charset="utf-8">
      <title>${t.name}</title>
      <style>
        body { font-family: Georgia, 'Times New Roman', serif; max-width: 44rem; margin: 2rem auto; padding: 0 1.5rem; color: #111; line-height: 1.55; }
        .meta { font-family: system-ui, sans-serif; font-size: .75rem; color: #555; margin-top: 2.5rem; border-top: 1px solid #ccc; padding-top: .75rem; }
        h1 { font-size: 1.5rem; } h2 { font-size: 1.2rem; margin-top: 1.8em; }
        table { border-collapse: collapse; width: 100%; font-size: .85em; }
        th, td { border: 1px solid #bbb; padding: .35rem .5rem; text-align: left; }
        blockquote { border-left: 3px solid #999; margin-left: 0; padding-left: 1rem; color: #444; }
      </style></head><body>
      ${el.innerHTML}
      <div class="meta">${t.name} — senast uppdaterad ${new Date(t.updated_at).toLocaleDateString('sv-SE')} — utskriven ${new Date().toLocaleString('sv-SE')} från den publicerade versionen.</div>
      </body></html>`);
    w.document.close();
    w.onload = () => w.print();
  };

  return (
    <div className="min-h-screen bg-muted/20 py-10 px-4">
      <Helmet>
        <title>Avtalsvillkor</title>
        <meta name="description" content="Publicerade allmänna villkor och tjänstevillkor." />
      </Helmet>
      <div className="max-w-3xl mx-auto space-y-4">
        <div className="mb-6">
          <h1 className="text-3xl font-bold">Avtalsvillkor</h1>
          <p className="text-muted-foreground mt-2">
            Här publiceras de villkorsversioner våra avtal hänvisar till. Varje
            avtal anger vilken version som gäller — den versionen ändras inte
            under avtalets bindningstid.
          </p>
        </div>

        {isLoading && <p className="text-sm text-muted-foreground">Laddar…</p>}
        {!isLoading && terms.length === 0 && (
          <p className="text-sm text-muted-foreground">Inga villkor är publicerade ännu.</p>
        )}

        {terms.map((t) => {
          const open = openId === t.id;
          return (
            <Card key={t.id}>
              <CardHeader
                className="cursor-pointer select-none py-4"
                onClick={() => setOpenId(open ? null : t.id)}
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-2 min-w-0">
                    <FileText className="h-4 w-4 shrink-0 text-primary" />
                    <span className="font-medium truncate">{t.name}</span>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className="text-xs text-muted-foreground hidden sm:inline">
                      Uppdaterad {new Date(t.updated_at).toLocaleDateString('sv-SE')}
                    </span>
                    <ChevronDown className={`h-4 w-4 transition-transform ${open ? 'rotate-180' : ''}`} />
                  </div>
                </div>
                {t.description && !open && (
                  <p className="text-sm text-muted-foreground mt-1 line-clamp-2">{t.description}</p>
                )}
              </CardHeader>
              {open && (
                <CardContent className="border-t pt-6">
                  <div className="flex justify-end mb-4">
                    <Button variant="outline" size="sm" className="gap-1.5" onClick={() => printTerm(t)}>
                      <Download className="h-4 w-4" />
                      Spara som PDF
                    </Button>
                  </div>
                  <article data-term-body={t.id} className="prose prose-sm dark:prose-invert max-w-none">
                    <ReactMarkdown remarkPlugins={[remarkGfm]}>{t.body_markdown}</ReactMarkdown>
                  </article>
                </CardContent>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
}
