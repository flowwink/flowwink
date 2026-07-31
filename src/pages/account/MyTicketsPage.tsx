import { useState } from 'react';
import { Helmet } from 'react-helmet-async';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Skeleton } from '@/components/ui/skeleton';
import { LifeBuoy, MessageSquare } from 'lucide-react';
import { usePlatformFormat } from '@/hooks/usePlatformFormat';
import {
  TICKET_STATUS_LABELS,
  TICKET_STATUS_COLORS,
  TICKET_PRIORITY_LABELS,
} from '@/hooks/useTickets';
import { useMyTickets, useMyTicketComments, useAddMyTicketReply } from '@/hooks/useMyTickets';

export default function MyTicketsPage() {
  const { formatDateTime } = usePlatformFormat();
  const { data: tickets = [], isLoading } = useMyTickets();
  const [openId, setOpenId] = useState<string | null>(null);
  const { data: comments = [] } = useMyTicketComments(openId);
  const reply = useAddMyTicketReply();
  const [draft, setDraft] = useState('');

  const submitReply = async (ticketId: string) => {
    if (!draft.trim()) return;
    await reply.mutateAsync({ ticketId, content: draft.trim() });
    setDraft('');
  };

  return (
    <>
      <Helmet><title>My support requests</title></Helmet>
      <div className="space-y-4">
        <div>
          <h2 className="text-2xl font-semibold">Support requests</h2>
          <p className="text-sm text-muted-foreground">
            Follow your open requests and reply to our team
          </p>
        </div>

        {isLoading && (
          <div className="space-y-2">
            {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-20 w-full" />)}
          </div>
        )}

        {!isLoading && tickets.length === 0 && (
          <Card>
            <CardContent className="py-12 text-center text-muted-foreground">
              <LifeBuoy className="h-8 w-8 mx-auto mb-3 opacity-60" />
              You have no support requests yet.
            </CardContent>
          </Card>
        )}

        {tickets.map((t) => {
          const isOpen = openId === t.id;
          return (
            <Card key={t.id}>
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <CardTitle className="text-base truncate">{t.subject}</CardTitle>
                    <p className="text-xs text-muted-foreground mt-1">
                      Opened {formatDateTime(t.created_at)} · {TICKET_PRIORITY_LABELS[t.priority]} priority
                    </p>
                  </div>
                  <Badge variant="outline" className={`text-xs shrink-0 ${TICKET_STATUS_COLORS[t.status]}`}>
                    {TICKET_STATUS_LABELS[t.status]}
                  </Badge>
                </div>
              </CardHeader>
              <CardContent className="space-y-3">
                {t.description && (
                  <p className="text-sm text-muted-foreground whitespace-pre-wrap line-clamp-3">
                    {t.description}
                  </p>
                )}

                <Button
                  variant="outline"
                  size="sm"
                  className="gap-1.5"
                  onClick={() => { setOpenId(isOpen ? null : t.id); setDraft(''); }}
                >
                  <MessageSquare className="h-3.5 w-3.5" />
                  {isOpen ? 'Hide conversation' : 'View conversation'}
                </Button>

                {isOpen && (
                  <div className="space-y-3 border-t pt-3">
                    {comments.length === 0 && (
                      <p className="text-sm text-muted-foreground">No replies yet.</p>
                    )}
                    {comments.map((c) => (
                      <div key={c.id} className="rounded-md bg-muted/40 p-3">
                        <p className="text-xs text-muted-foreground mb-1">
                          {c.author_name || (c.author_type === 'customer' ? 'You' : 'Support')} ·{' '}
                          {formatDateTime(c.created_at)}
                        </p>
                        <p className="text-sm whitespace-pre-wrap">{c.content}</p>
                      </div>
                    ))}

                    {t.status !== 'closed' && (
                      <div className="space-y-2">
                        <Textarea
                          value={draft}
                          onChange={(e) => setDraft(e.target.value)}
                          placeholder="Write a reply…"
                          rows={3}
                        />
                        <Button
                          size="sm"
                          disabled={!draft.trim() || reply.isPending}
                          onClick={() => submitReply(t.id)}
                        >
                          Send reply
                        </Button>
                      </div>
                    )}
                  </div>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>
    </>
  );
}
