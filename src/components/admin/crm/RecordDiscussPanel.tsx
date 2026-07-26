import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';
import { Textarea } from '@/components/ui/textarea';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Send, MessageSquare, Phone, Mail, Users, Loader2, ArrowUpRight } from 'lucide-react';
import { useLogActivity, type DiscussActivityType } from '@/hooks/useLogActivity';
import { useSendLeadEmail } from '@/hooks/useSendLeadEmail';
import { useCompanyMailbox } from '@/hooks/useCompanyMailbox';
import { UnifiedTimeline } from './UnifiedTimeline';

interface RecordDiscussPanelProps {
  leadId?: string;
  email?: string;
  /** Hide the timeline (e.g. when caller already renders one) */
  hideTimeline?: boolean;
}

type ComposerTab = DiscussActivityType;

/** Note, Call and Meeting record something that already happened outside the
 *  system. Email is different — the system can send, so that tab composes. */
const TABS: { value: ComposerTab; label: string; icon: React.ElementType; placeholder: string }[] = [
  { value: 'note', label: 'Note', icon: MessageSquare, placeholder: 'Internal note — visible to your team only…' },
  { value: 'call', label: 'Call', icon: Phone, placeholder: 'What was discussed on the call?' },
  { value: 'email', label: 'Email', icon: Mail, placeholder: 'Write your email…' },
  { value: 'meeting', label: 'Meeting', icon: Users, placeholder: 'Meeting notes, decisions, next steps…' },
];

/**
 * Discuss panel: activity logger for what happened offline, real composer for
 * email. Drop in on any lead/customer record.
 */
export function RecordDiscussPanel({ leadId, email, hideTimeline }: RecordDiscussPanelProps) {
  const [type, setType] = useState<ComposerTab>('note');
  const [body, setBody] = useState('');
  const [subject, setSubject] = useState('');
  const log = useLogActivity();
  const send = useSendLeadEmail();
  const { data: mailbox } = useCompanyMailbox();

  const activeTab = TABS.find(t => t.value === type)!;
  const isEmail = type === 'email';
  const senderLabel = mailbox?.email_address ?? 'company mailbox';
  const pending = isEmail ? send.isPending : log.isPending;
  const canSubmit = isEmail
    ? !!body.trim() && !!subject.trim() && !!email
    : !!body.trim();

  const submit = () => {
    if (!canSubmit || pending) return;

    if (isEmail) {
      send.mutate(
        { leadId, to: email!, subject: subject.trim(), body: body.trim() },
        { onSuccess: () => { setBody(''); setSubject(''); } },
      );
      return;
    }

    log.mutate(
      { leadId, email, type, body: body.trim() },
      { onSuccess: () => { setBody(''); setSubject(''); } },
    );
  };

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-base">Discuss</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <Tabs value={type} onValueChange={(v) => setType(v as ComposerTab)}>
            <TabsList className="h-9">
              {TABS.map(t => {
                const Icon = t.icon;
                return (
                  <TabsTrigger key={t.value} value={t.value} className="text-xs h-7">
                    <Icon className="h-3.5 w-3.5 mr-1.5" />
                    {t.label}
                  </TabsTrigger>
                );
              })}
            </TabsList>

            {TABS.map(t => (
              <TabsContent key={t.value} value={t.value} className="space-y-2 mt-3">
                {t.value === 'email' && (
                  <div className="rounded-md border border-border bg-muted/40 px-3 py-2 text-xs text-muted-foreground space-y-0.5">
                    <div className="flex items-center gap-1.5 text-foreground">
                      <ArrowUpRight className="h-3.5 w-3.5 text-blue-600" />
                      <span className="font-medium">Sends from {senderLabel}</span>
                    </div>
                    <p>
                      {email
                        ? <>Replies come back to that mailbox and stay linked to this contact.</>
                        : <>This contact has no email address — add one to send.</>}
                    </p>
                  </div>
                )}
                {t.value === 'email' && (
                  <Input
                    placeholder="Subject"
                    value={subject}
                    onChange={(e) => setSubject(e.target.value)}
                    className="text-sm"
                  />
                )}
                <Textarea
                  placeholder={t.placeholder}
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  rows={t.value === 'email' ? 6 : 3}
                  className="text-sm resize-none"
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
                      e.preventDefault();
                      submit();
                    }
                  }}
                />
              </TabsContent>
            ))}
          </Tabs>

          <div className="flex items-center justify-between">
            <p className="text-xs text-muted-foreground">⌘/Ctrl + Enter to send</p>
            <Button size="sm" onClick={submit} disabled={!canSubmit || pending}>
              {pending ? (
                <Loader2 className="h-3.5 w-3.5 mr-1.5 animate-spin" />
              ) : (
                <Send className="h-3.5 w-3.5 mr-1.5" />
              )}
              {isEmail ? 'Send email' : `Log ${activeTab.label.toLowerCase()}`}
            </Button>
          </div>
        </CardContent>
      </Card>

      {!hideTimeline && <UnifiedTimeline leadId={leadId} email={email} />}
    </div>
  );
}
