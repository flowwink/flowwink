import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Card, CardContent } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import {
  Mail,
  Loader2,
  CheckCircle2,
  AlertCircle,
  Send,
  Unplug,
  Info,
  User,
} from 'lucide-react';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';

export interface ComposioConnectedAccount {
  id?: string;
  name?: string;
  appName?: string;
  status?: string;
  user_id?: string;
  toolkit?: { slug?: string };
}

function toolkitOf(account: ComposioConnectedAccount) {
  return (account.toolkit?.slug || account.appName || account.name || '').toLowerCase();
}

/**
 * Resolve the actual mailbox behind a Composio Gmail connection.
 * The connected_accounts response only carries OAuth tokens, so we ask
 * Gmail itself via the existing composio-proxy `execute` action.
 */
function useGmailIdentity(account: ComposioConnectedAccount, enabled: boolean) {
  const entityId = account.user_id || 'default';
  return useQuery({
    queryKey: ['composio-gmail-identity', account.id, entityId],
    enabled,
    staleTime: 10 * 60 * 1000,
    gcTime: 30 * 60 * 1000,
    retry: 0,
    queryFn: async () => {
      const { data, error } = await supabase.functions.invoke('composio-proxy', {
        body: {
          action: 'execute',
          entity_id: entityId,
          params: {
            action_name: 'GMAIL_GET_PROFILE',
            toolkit: 'gmail',
            input: {},
          },
        },
      });
      if (error) throw error;
      const r = data?.result;
      const payload = r?.data?.response_data || r?.data || r || {};
      const email: string | undefined =
        payload.emailAddress || payload.email_address || payload.email;
      if (!email) throw new Error('Gmail profile did not include an address');
      return {
        email,
        messagesTotal: payload.messagesTotal ?? payload.messages_total ?? null,
      };
    },
  });
}

interface RowProps {
  account: ComposioConnectedAccount;
  onDisconnect: (account: ComposioConnectedAccount) => Promise<void> | void;
  disconnecting?: boolean;
}

function AccountRow({ account, onDisconnect, disconnecting }: RowProps) {
  const isGmail = toolkitOf(account).includes('gmail');
  const entityId = account.user_id || 'default';
  const isActive = (account.status || '').toLowerCase() === 'active';
  const identity = useGmailIdentity(account, isGmail && isActive);

  const [testOpen, setTestOpen] = useState(false);
  const [testTo, setTestTo] = useState('');
  const [sending, setSending] = useState(false);
  const [lastSentFrom, setLastSentFrom] = useState<string | null>(null);

  const handleTestSend = async () => {
    if (!testTo.trim()) {
      toast.error('Enter a recipient address');
      return;
    }
    setSending(true);
    setLastSentFrom(null);
    try {
      const { data, error } = await supabase.functions.invoke('composio-proxy', {
        body: {
          action: 'gmail_send',
          entity_id: entityId,
          params: {
            to: testTo.trim(),
            subject: 'FlowWink test email',
            body: 'This is a test email sent from FlowWink through the connected Gmail account.',
            account_id: account.id,
          },
        },
      });
      if (error) throw error;
      const result = data?.result;
      const ok = result?.successful || result?.successfull || result?.success;
      if (!ok) {
        throw new Error(
          typeof result?.error === 'string' ? result.error : 'Send failed — check the connection',
        );
      }
      const from =
        result?.data?.response_data?.from ||
        identity.data?.email ||
        'the connected account';
      setLastSentFrom(from);
      toast.success(`Test email sent from ${from}`);
      setTestTo('');
    } catch (err) {
      logger.error('[ComposioAccountsList] Test send failed:', err);
      toast.error(err instanceof Error ? err.message : 'Failed to send test email');
    } finally {
      setSending(false);
    }
  };

  return (
    <Card className="border-muted">
      <CardContent className="py-3 px-4 space-y-3">
        <div className="flex flex-col gap-3">
          <div className="flex items-start gap-3 min-w-0 flex-1">
            <div className="h-8 w-8 shrink-0 rounded-lg bg-primary/10 flex items-center justify-center">
              <Mail className="h-4 w-4 text-primary" />
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 flex-wrap">
                <p className="text-sm font-medium capitalize">
                  {account.toolkit?.slug || account.appName || account.name || 'Connected app'}
                </p>
                <Badge
                  variant={isActive ? 'secondary' : 'destructive'}
                  className="text-[10px]"
                >
                  {isActive ? (
                    <CheckCircle2 className="h-3 w-3 mr-1 text-primary" />
                  ) : null}
                  {isActive ? 'Connected' : (account.status || 'Inactive')}
                </Badge>
              </div>

              {/* Identity */}
              <div className="mt-1 flex items-center gap-1.5 text-xs min-w-0">
                <User className="h-3 w-3 text-muted-foreground shrink-0" />
                {!isGmail ? (
                  <span className="text-muted-foreground truncate">Account: {entityId}</span>
                ) : !isActive ? (
                  <span className="text-destructive">
                    Connection expired — disconnect and reconnect Gmail
                  </span>
                ) : identity.isLoading ? (
                  <span className="text-muted-foreground inline-flex items-center gap-1">
                    <Loader2 className="h-3 w-3 animate-spin" /> Resolving mailbox…
                  </span>
                ) : identity.data?.email ? (
                  <span className="font-medium text-foreground truncate">{identity.data.email}</span>
                ) : (
                  <span className="text-muted-foreground">
                    Mailbox unknown — could not read the Gmail profile
                  </span>
                )}
              </div>

              {isGmail && isActive && (
                <p className="mt-1 text-xs text-muted-foreground">
                  FlowPilot can read and send mail as this account.
                </p>
              )}
              <p className="mt-0.5 text-[11px] text-muted-foreground truncate">
                Composio user_id: <span className="font-mono">{entityId}</span>
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2 flex-wrap">

            {isGmail && isActive && (
              <Button
                variant="outline"
                size="sm"
                className="text-xs"
                onClick={() => setTestOpen(v => !v)}
              >
                <Send className="h-3 w-3 mr-1" />
                Send test email
              </Button>
            )}
            <Button
              variant="outline"
              size="sm"
              className="text-xs border-destructive/30 text-destructive hover:bg-destructive/10 hover:text-destructive"
              disabled={disconnecting}
              onClick={() => onDisconnect(account)}
            >
              {disconnecting ? (
                <Loader2 className="h-3 w-3 mr-1 animate-spin" />
              ) : (
                <Unplug className="h-3 w-3 mr-1" />
              )}
              Disconnect
            </Button>
          </div>
        </div>

        {isGmail && testOpen && (
          <>
            <Separator />
            <div className="space-y-2">
              <div className="flex gap-2">
                <Input
                  placeholder="Recipient address"
                  value={testTo}
                  onChange={e => setTestTo(e.target.value)}
                  className="h-8 text-xs"
                />
                <Button size="sm" className="text-xs" onClick={handleTestSend} disabled={sending}>
                  {sending ? (
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  ) : (
                    <Send className="h-3.5 w-3.5" />
                  )}
                </Button>
              </div>
              {lastSentFrom && (
                <p className="text-xs text-primary">Sent from {lastSentFrom}</p>
              )}
              <p className="text-[11px] text-muted-foreground">
                Gmail always sends as the connected account — a per-user From address is ignored on
                this transport.
              </p>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}

interface Props {
  accounts: ComposioConnectedAccount[];
  isLoading?: boolean;
  disconnectingId?: string | null;
  onDisconnect: (account: ComposioConnectedAccount) => Promise<void> | void;
  onConnect?: () => void;
}

export function ComposioAccountsList({
  accounts,
  isLoading,
  disconnectingId,
  onDisconnect,
  onConnect,
}: Props) {
  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!accounts.length) {
    return (
      <Card className="border-dashed border-muted-foreground/30">
        <CardContent className="py-6 text-center space-y-3">
          <AlertCircle className="h-7 w-7 text-muted-foreground/40 mx-auto" />
          <p className="text-sm text-muted-foreground">No mailbox connected yet</p>
          {onConnect && (
            <Button size="sm" className="text-xs" onClick={onConnect}>
              <Mail className="h-3 w-3 mr-1" />
              Connect Gmail
            </Button>
          )}
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-2">
      {accounts.map((account, i) => (
        <AccountRow
          key={account.id || i}
          account={account}
          onDisconnect={onDisconnect}
          disconnecting={disconnectingId === account.id}
        />
      ))}
      <div className="flex items-start gap-2 rounded-md border border-border bg-muted/40 p-3">
        <Info className="h-3.5 w-3.5 text-muted-foreground mt-0.5 shrink-0" />
        <p className="text-xs text-muted-foreground">
          Replies to a connected mailbox stay visible to the CRM and FlowPilot because Composio can
          read it. A reply-to pointing at a personal mailbox FlowWink has not connected lands outside
          the system.
        </p>
      </div>
    </div>
  );
}
