/**
 * Invite a colleague by email, with the functional role they need from the
 * first sign-in. Closes the gap between create-user (right role, but you set
 * the password) and invite-employee (real email, but wrong roles): the
 * invitee sets their own password AND lands already holding e.g. 'sales'.
 */
import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { useQueryClient } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter,
  DialogHeader, DialogTitle, DialogTrigger,
} from '@/components/ui/dialog';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { UserPlus, Loader2 } from 'lucide-react';
import type { AppRole } from '@/types/cms';
import { ROLE_LABELS, ROLE_DESCRIPTIONS, FUNCTIONAL_ROLES } from '@/types/cms';

// admin + the functional roles — the roles a colleague can be invited AS.
// Not customer (that is the portal, a different flow) and not the legacy
// writer/approver roles.
const INVITABLE: AppRole[] = ['admin', ...FUNCTIONAL_ROLES];

export function InviteColleagueDialog() {
  const { toast } = useToast();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState('');
  const [fullName, setFullName] = useState('');
  const [role, setRole] = useState<AppRole>('sales');
  const [pending, setPending] = useState(false);

  const submit = async () => {
    setPending(true);
    try {
      const { data, error } = await supabase.functions.invoke('invite-colleague', {
        body: { email, role, full_name: fullName || undefined },
      });
      if (error) throw new Error(error.message);
      if (!(data as { success?: boolean })?.success) {
        throw new Error((data as { error?: string })?.error ?? 'Invite failed');
      }
      const status = (data as { status?: string }).status;
      toast({
        title: status === 'granted_existing' ? 'Role granted' : 'Invitation sent',
        description: status === 'granted_existing'
          ? `${email} already had an account — granted ${ROLE_LABELS[role]}.`
          : `${email} will receive an email to set a password and join as ${ROLE_LABELS[role]}.`,
      });
      qc.invalidateQueries({ queryKey: ['admin-users'] });
      setOpen(false);
      setEmail(''); setFullName(''); setRole('sales');
    } catch (e) {
      toast({ title: 'Error', description: (e as Error).message, variant: 'destructive' });
    } finally {
      setPending(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          <UserPlus className="h-4 w-4 mr-2" /> Invite colleague
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Invite a colleague</DialogTitle>
          <DialogDescription>
            They get an email to set their own password and join with the role
            you pick — no shared password.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="invite-email">Email</Label>
            <Input
              id="invite-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="colleague@company.com"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="invite-name">Name (optional)</Label>
            <Input
              id="invite-name"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              placeholder="Anna Lindqvist"
            />
          </div>
          <div className="space-y-2">
            <Label>Role</Label>
            <Select value={role} onValueChange={(v) => setRole(v as AppRole)}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {INVITABLE.map((r) => (
                  <SelectItem key={r} value={r}>{ROLE_LABELS[r]}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="text-xs text-muted-foreground">{ROLE_DESCRIPTIONS[role]}</p>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={submit} disabled={pending || !email}>
            {pending && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
            Send invite
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
