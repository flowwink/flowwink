import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Loader2, Trash2 } from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "sonner";
import { useIsModuleEnabled } from "@/hooks/useModules";
import { Link } from "react-router-dom";

/**
 * Inbound mailbox registry.
 *
 * Conceptually this is Email Router territory — it describes WHICH incoming
 * addresses FlowWink should watch and WHAT to do with replies. It survives
 * Composio OAuth rotations because it's routing config, not a live token.
 *
 * The primary route mode is CRM: an outbound cold email to a lead comes back
 * as a reply and lands on the contact/lead card via `outbound_communications`
 * + `inbound_communications`. Tickets are an optional second path, gated by
 * the tickets module.
 */
type RouteMode = "crm_only" | "crm_then_ticket" | "ticket_only";

interface Props {
  /**
   * Which surface is rendering this section — used only to reorder the
   * default route-mode explanation. Both surfaces show the same controls.
   */
  emphasis?: "crm" | "tickets";
  isGmailConnected: boolean;
}

export function InboundMailboxesSection({ emphasis = "crm", isGmailConnected }: Props) {
  const ticketsEnabled = useIsModuleEnabled("tickets");
  const [email, setEmail] = useState("");
  const [composioAccountId, setComposioAccountId] = useState("");
  const [registering, setRegistering] = useState(false);
  const [activatingWatch, setActivatingWatch] = useState<string | null>(null);
  const [enablingTrigger, setEnablingTrigger] = useState<string | null>(null);

  const webhookUrl = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/composio-webhook`;

  const { data: accounts, isLoading, refetch } = useQuery({
    queryKey: ["inbound-email-accounts"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("inbound_email_accounts")
        .select("*")
        .order("created_at", { ascending: true });
      if (error) throw error;
      return data || [];
    },
    staleTime: 15 * 1000,
  });

  const handleRegister = async () => {
    if (!email.trim()) {
      toast.error("Enter an email address");
      return;
    }
    setRegistering(true);
    try {
      const { error } = await supabase.from("inbound_email_accounts").insert({
        provider: "composio_gmail",
        email_address: email.trim(),
        composio_account_id: composioAccountId.trim() || null,
        is_shared: true,
        enabled: true,
        // Default: land replies on the CRM record (contact/lead card).
        route_mode: emphasis === "tickets" && ticketsEnabled ? "crm_then_ticket" : "crm_only",
      } as any);
      if (error) throw error;
      toast.success("Mailbox registered");
      setEmail("");
      setComposioAccountId("");
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to register");
    } finally {
      setRegistering(false);
    }
  };

  const handleActivateWatch = async (accountId: string, composioAccId: string | null) => {
    setActivatingWatch(accountId);
    try {
      const { data, error } = await supabase.functions.invoke("composio-proxy", {
        body: { action: "gmail_watch", params: { account_id: composioAccId }, entity_id: "default" },
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
      await supabase.from("inbound_email_accounts").update({ watch_expires_at: expiresAt }).eq("id", accountId);
      toast.success("Gmail Watch activated — push events will start arriving");
      refetch();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to activate watch");
    } finally {
      setActivatingWatch(null);
    }
  };

  const handleEnableTrigger = async (accountId: string, composioAccId: string | null) => {
    setEnablingTrigger(accountId);
    try {
      const { data, error } = await supabase.functions.invoke("composio-proxy", {
        body: {
          action: "enable_trigger",
          params: { trigger_slug: "GMAIL_NEW_GMAIL_MESSAGE", account_id: composioAccId, toolkit: "gmail" },
          entity_id: "default",
        },
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);
      toast.success("Composio trigger enabled — replies will now arrive via webhook");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to enable trigger");
    } finally {
      setEnablingTrigger(null);
    }
  };

  const handleToggleEnabled = async (accountId: string, enabled: boolean) => {
    await supabase.from("inbound_email_accounts").update({ enabled }).eq("id", accountId);
    refetch();
  };

  const handleRouteChange = async (accountId: string, mode: RouteMode) => {
    const { error } = await supabase
      .from("inbound_email_accounts")
      .update({ route_mode: mode } as any)
      .eq("id", accountId);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Route updated");
    refetch();
  };

  const handleRemove = async (accountId: string, emailAddress: string) => {
    if (!confirm(`Remove inbound mailbox "${emailAddress}"? Routing rules for this address will be lost.`)) return;
    const { error } = await supabase.from("inbound_email_accounts").delete().eq("id", accountId);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success("Mailbox removed");
    refetch();
  };

  return (
    <div className="space-y-4">
      <div className="text-xs text-muted-foreground">
        {emphasis === "crm" ? (
          <>
            Primary use case: a cold outbound email is sent to a lead — the reply lands on the
            contact/lead card and in <Link to="/admin/communications" className="underline">Communications</Link>.
            Optionally, unmatched replies can create a ticket if the Tickets module is enabled.
          </>
        ) : (
          <>
            Inbound mailboxes route replies to tickets. The default routing sends replies to the
            CRM record (contact/lead card) first — switch a mailbox to <em>Ticket only</em> or
            <em> CRM then ticket</em> if unmatched mail should escalate here.
          </>
        )}
      </div>

      {/* Webhook URL */}
      <Card className="border-muted">
        <CardContent className="py-3 px-4 space-y-2">
          <p className="text-xs font-medium">Composio webhook URL</p>
          <p className="text-[10px] text-muted-foreground">
            Paste this into Composio dashboard → Project Settings → Webhooks so trigger events reach FlowWink.
          </p>
          <div className="flex gap-1">
            <Input value={webhookUrl} readOnly className="h-8 text-xs font-mono" />
            <Button
              size="sm"
              variant="outline"
              className="text-xs h-8"
              onClick={() => {
                navigator.clipboard.writeText(webhookUrl);
                toast.success("Copied");
              }}
            >
              Copy
            </Button>
          </div>
        </CardContent>
      </Card>

      {!isGmailConnected && (
        <Card className="border-dashed border-amber-500/40 bg-amber-500/5">
          <CardContent className="py-3 px-4 text-xs">
            Connect Gmail in <Link to="/admin/integrations" className="underline">Integrations</Link> first
            so Composio knows which account this mailbox lives in.
          </CardContent>
        </Card>
      )}

      {isLoading ? (
        <div className="flex justify-center py-6">
          <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
        </div>
      ) : accounts && accounts.length > 0 ? (
        <div className="space-y-2">
          {accounts.map((acc: any) => {
            const watchActive = acc.watch_expires_at && new Date(acc.watch_expires_at) > new Date();
            const routeMode: RouteMode = (acc.route_mode as RouteMode) || "crm_only";
            return (
              <Card key={acc.id} className="border-muted">
                <CardContent className="py-3 px-4 space-y-3">
                  <div className="flex items-center justify-between gap-2">
                    <div className="min-w-0">
                      <p className="text-sm font-medium truncate">{acc.email_address}</p>
                      <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                        <Badge variant={acc.enabled ? "default" : "secondary"} className="text-[10px]">
                          {acc.enabled ? "Enabled" : "Disabled"}
                        </Badge>
                        <Badge variant={watchActive ? "default" : "outline"} className="text-[10px]">
                          {watchActive ? "Watch active" : "No watch"}
                        </Badge>
                        {acc.is_shared && <Badge variant="outline" className="text-[10px]">Shared</Badge>}
                      </div>
                    </div>
                    <div className="flex gap-1 shrink-0 flex-wrap justify-end">
                      <Button
                        size="sm"
                        variant="outline"
                        className="text-xs h-7"
                        onClick={() => handleEnableTrigger(acc.id, acc.composio_account_id)}
                        disabled={enablingTrigger === acc.id || !isGmailConnected}
                        title="Enable Composio GMAIL_NEW_GMAIL_MESSAGE trigger so replies are pushed to FlowWink"
                      >
                        {enablingTrigger === acc.id ? <Loader2 className="h-3 w-3 animate-spin" /> : "Enable trigger"}
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="text-xs h-7"
                        onClick={() => handleActivateWatch(acc.id, acc.composio_account_id)}
                        disabled={activatingWatch === acc.id || !isGmailConnected}
                      >
                        {activatingWatch === acc.id ? (
                          <Loader2 className="h-3 w-3 animate-spin" />
                        ) : watchActive ? "Renew watch" : "Activate watch"}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-xs h-7"
                        onClick={() => handleToggleEnabled(acc.id, !acc.enabled)}
                      >
                        {acc.enabled ? "Disable" : "Enable"}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="text-xs h-7 text-destructive hover:text-destructive"
                        onClick={() => handleRemove(acc.id, acc.email_address)}
                        title="Remove this inbound mailbox"
                      >
                        <Trash2 className="h-3 w-3" />
                      </Button>
                    </div>
                  </div>

                  {/* Route mode selector */}
                  <div className="flex items-center gap-2 pt-2 border-t border-border/60">
                    <Label className="text-[10px] uppercase tracking-wide text-muted-foreground shrink-0">Route replies to</Label>
                    <Select
                      value={routeMode}
                      onValueChange={(v) => handleRouteChange(acc.id, v as RouteMode)}
                    >
                      <SelectTrigger className="h-7 text-xs w-full max-w-[280px]">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="crm_only">
                          CRM only — attach to contact/lead
                        </SelectItem>
                        <SelectItem value="crm_then_ticket" disabled={!ticketsEnabled}>
                          CRM, else ticket {ticketsEnabled ? "" : "(enable Tickets module)"}
                        </SelectItem>
                        <SelectItem value="ticket_only" disabled={!ticketsEnabled}>
                          Ticket only {ticketsEnabled ? "" : "(enable Tickets module)"}
                        </SelectItem>
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="text-[10px] text-muted-foreground space-y-0.5">
                    {acc.last_received_at && <div>Last received: {new Date(acc.last_received_at).toLocaleString()}</div>}
                    {acc.watch_expires_at && <div>Watch expires: {new Date(acc.watch_expires_at).toLocaleString()}</div>}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      ) : (
        <Card className="border-dashed border-muted-foreground/30">
          <CardContent className="py-4 text-center text-xs text-muted-foreground">
            No inbound mailbox registered yet.
          </CardContent>
        </Card>
      )}

      {/* Register form */}
      <Card className="border-muted">
        <CardContent className="py-3 px-4 space-y-2">
          <p className="text-xs font-medium">Register company inbox</p>
          <Input
            placeholder="info@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="h-8 text-xs"
          />
          <Input
            placeholder="Composio connected_account_id (optional)"
            value={composioAccountId}
            onChange={(e) => setComposioAccountId(e.target.value)}
            className="h-8 text-xs font-mono"
          />
          <Button size="sm" className="w-full text-xs" onClick={handleRegister} disabled={registering || !email.trim()}>
            {registering && <Loader2 className="h-3 w-3 mr-1 animate-spin" />}
            Register mailbox
          </Button>
          <p className="text-[10px] text-muted-foreground">
            Leave account id empty to let the webhook auto-match by the inbound message.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
