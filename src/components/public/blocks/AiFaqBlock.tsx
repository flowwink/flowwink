import { useMemo, useState } from 'react';
import { Sparkles, Search, Loader2, Send } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { BlockSection, SectionHeading } from './_shared';
import { cn } from '@/lib/utils';

export interface AiFaqItem {
  id: string;
  question: string;
  answer: string;
}

export interface AiFaqBlockData {
  title?: string;
  subtitle?: string;
  eyebrow?: string;
  items?: AiFaqItem[];
  searchPlaceholder?: string;
  askAiLabel?: string;
  emptyStateText?: string;
}

interface Props {
  data: AiFaqBlockData;
}

export function AiFaqBlock({ data }: Props) {
  const {
    title = 'Frequently asked questions',
    subtitle,
    eyebrow,
    items = [],
    searchPlaceholder = 'Ask a question or search…',
    askAiLabel = 'Ask AI',
    emptyStateText = "No matching answers. Try asking the assistant instead.",
  } = data;

  const [query, setQuery] = useState('');
  const [dialogOpen, setDialogOpen] = useState(false);
  const [aiAnswer, setAiAnswer] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter(
      (i) =>
        i.question.toLowerCase().includes(q) ||
        i.answer.toLowerCase().includes(q),
    );
  }, [items, query]);

  const askAi = async () => {
    const q = query.trim();
    if (!q) return;
    setDialogOpen(true);
    setLoading(true);
    setError(null);
    setAiAnswer('');
    try {
      const context = items
        .slice(0, 20)
        .map((i) => `Q: ${i.question}\nA: ${i.answer}`)
        .join('\n\n');
      const res = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/chat-completion`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY}`,
          },
          body: JSON.stringify({
            messages: [
              {
                role: 'system',
                content: `You are a helpful assistant answering questions on a website. Use the FAQ context below when relevant, and answer concisely (2-4 sentences). If unsure, say so.\n\n### FAQ context\n${context || '(no FAQ provided)'}`,
              },
              { role: 'user', content: q },
            ],
          }),
        },
      );
      if (!res.ok) throw new Error(`Assistant unavailable (${res.status})`);
      const json = await res.json();
      const content =
        json?.choices?.[0]?.message?.content ??
        json?.message ??
        json?.content ??
        '';
      setAiAnswer(String(content).trim() || 'No response.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong');
    } finally {
      setLoading(false);
    }
  };

  return (
    <BlockSection>
      <div className="max-w-3xl mx-auto">
        <SectionHeading
          eyebrow={eyebrow}
          title={title}
          lead={subtitle}
          align="center"
        />

        <form
          onSubmit={(e) => {
            e.preventDefault();
            askAi();
          }}
          className="mt-8 flex items-center gap-2 rounded-full border border-border/70 bg-card shadow-sm px-3 py-2 focus-within:border-primary/60 focus-within:ring-2 focus-within:ring-primary/20 transition"
        >
          <Search className="h-4 w-4 text-muted-foreground shrink-0 ml-1" />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={searchPlaceholder}
            className="border-0 shadow-none focus-visible:ring-0 h-10 bg-transparent"
          />
          <Button
            type="submit"
            size="sm"
            className={cn('rounded-full gap-1.5', !query.trim() && 'opacity-70')}
            disabled={!query.trim()}
          >
            <Sparkles className="h-3.5 w-3.5" />
            {askAiLabel}
          </Button>
        </form>

        <div className="mt-8">
          {filtered.length > 0 ? (
            <Accordion type="single" collapsible className="w-full">
              {filtered.map((item) => (
                <AccordionItem key={item.id} value={item.id}>
                  <AccordionTrigger className="text-left text-base font-medium">
                    {item.question}
                  </AccordionTrigger>
                  <AccordionContent className="text-muted-foreground leading-relaxed whitespace-pre-line">
                    {item.answer}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          ) : (
            <div className="rounded-[var(--radius-block,1rem)] border border-dashed border-border/70 p-6 text-center">
              <p className="text-sm text-muted-foreground mb-4">{emptyStateText}</p>
              <Button variant="outline" onClick={askAi} disabled={!query.trim()}>
                <Sparkles className="h-4 w-4 mr-2" />
                Ask the assistant
              </Button>
            </div>
          )}
        </div>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Sparkles className="h-4 w-4 text-primary" />
              Assistant answer
            </DialogTitle>
            <DialogDescription className="italic">"{query}"</DialogDescription>
          </DialogHeader>
          <div className="min-h-[80px]">
            {loading ? (
              <div className="flex items-center gap-2 text-muted-foreground text-sm">
                <Loader2 className="h-4 w-4 animate-spin" /> Thinking…
              </div>
            ) : error ? (
              <p className="text-sm text-destructive">{error}</p>
            ) : (
              <p className="text-sm leading-relaxed whitespace-pre-line">
                {aiAnswer}
              </p>
            )}
          </div>
          <div className="pt-2 flex justify-end">
            <Button variant="outline" size="sm" onClick={() => setDialogOpen(false)}>
              Close
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </BlockSection>
  );
}
