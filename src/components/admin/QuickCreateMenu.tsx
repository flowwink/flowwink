import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Plus, UserPlus, Briefcase, CheckSquare, LifeBuoy, HandCoins, FileSignature,
  Building2, FileText, Receipt, ClipboardList, User, Newspaper, FileCode,
  Megaphone, Package, Truck, Image as ImageIcon, FolderKanban, BookOpen, Clock,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
  DropdownMenuLabel, DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { CreateLeadDialog } from '@/components/admin/CreateLeadDialog';
import { CreateTaskDialog } from '@/components/admin/CreateTaskDialog';
import { CreateTicketDialog } from '@/components/admin/tickets/CreateTicketDialog';
import { useEnabledModules } from '@/hooks/useModules';
import { useModuleAccess } from '@/hooks/useRoleModuleAccess';

type DialogKey = 'lead' | 'task' | 'ticket' | null;

type QuickAction =
  | { kind: 'dialog'; key: Exclude<DialogKey, null>; label: string; icon: React.ElementType; moduleId?: string }
  | { kind: 'nav'; href: string; label: string; icon: React.ElementType; moduleId?: string };

// Same filter as the ⌘K quick-create shortcuts: module enabled + the matrix
// (role_module_access) via useModuleAccess. No hardcoded role lists (#102) —
// a role granted e.g. pages in Role Permissions gets the Page button.
const ACTIONS: QuickAction[] = [
  { kind: 'dialog', key: 'lead',   label: 'Contact / lead',  icon: UserPlus,      moduleId: 'leads' },
  { kind: 'nav',    href: '/admin/deals?new=1',           label: 'Deal',           icon: HandCoins,     moduleId: 'deals' },
  { kind: 'nav',    href: '/admin/quotes?new=1',          label: 'Quote',          icon: FileSignature, moduleId: 'quotes' },
  { kind: 'nav',    href: '/admin/companies?new=1',       label: 'Company',        icon: Building2,     moduleId: 'companies' },
  { kind: 'nav',    href: '/admin/invoices?new=1',        label: 'Invoice',        icon: FileText,      moduleId: 'invoicing' },
  { kind: 'nav',    href: '/admin/expenses?new=1',        label: 'Expense',        icon: Receipt,       moduleId: 'expenses' },
  { kind: 'nav',    href: '/admin/purchase-orders?new=1', label: 'Purchase order', icon: ClipboardList, moduleId: 'purchasing' },
  { kind: 'dialog', key: 'ticket', label: 'Ticket',         icon: LifeBuoy,      moduleId: 'tickets' },
  { kind: 'nav',    href: '/admin/hr?new=1',              label: 'Employee',       icon: User,          moduleId: 'hr' },
  { kind: 'nav',    href: '/admin/recruitment?new=1',     label: 'Job posting',    icon: Briefcase,     moduleId: 'recruitment' },
  { kind: 'nav',    href: '/admin/blog/new',              label: 'Blog post',      icon: Newspaper,     moduleId: 'blog' },
  { kind: 'nav',    href: '/admin/pages/new',             label: 'Page',           icon: FileCode,      moduleId: 'pages' },
  { kind: 'nav',    href: '/admin/campaigns?new=1',       label: 'Campaign',       icon: Megaphone,     moduleId: 'paidGrowth' },
  { kind: 'nav',    href: '/admin/media?upload=1',        label: 'Media upload',   icon: ImageIcon,     moduleId: 'mediaLibrary' },
  { kind: 'nav',    href: '/admin/projects?new=1',        label: 'Project',        icon: FolderKanban,  moduleId: 'projects' },
  { kind: 'nav',    href: '/admin/products?new=1',        label: 'Product',        icon: Package,       moduleId: 'ecommerce' },
  { kind: 'nav',    href: '/admin/vendors?new=1',         label: 'Vendor',         icon: Truck,         moduleId: 'purchasing' },
  { kind: 'nav',    href: '/admin/accounting?tab=journal&new=1', label: 'Journal entry', icon: BookOpen, moduleId: 'accounting' },
  { kind: 'nav',    href: '/admin/timesheets?tab=entries&new=1', label: 'Time entry',    icon: Clock,    moduleId: 'projects' },
  // Task has no moduleId: available to every staff member — the universal capture surface.
  { kind: 'dialog', key: 'task',   label: 'Activity / task', icon: CheckSquare },
];

export function QuickCreateMenu() {
  const navigate = useNavigate();
  const [active, setActive] = useState<DialogKey>(null);
  const { canAccess } = useModuleAccess();
  const enabledModules = useEnabledModules();
  const enabledModuleIds = useMemo(() => new Set<string>(enabledModules), [enabledModules]);

  const visible = useMemo(() => {
    return ACTIONS.filter((a) => {
      if (a.moduleId && !enabledModuleIds.has(a.moduleId)) return false;
      // The matrix is the only dial (#102): moduleId + role_module_access.
      // Actions without a moduleId (task capture) show for all staff.
      return a.moduleId ? canAccess(a.moduleId) : true;
    });
  }, [enabledModuleIds, canAccess]);

  // Keyboard shortcut: "c" opens menu via simulated click target
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || (e.target as HTMLElement)?.isContentEditable) return;
      if (e.key === 'c' && !e.metaKey && !e.ctrlKey && !e.altKey) {
        e.preventDefault();
        document.getElementById('quick-create-trigger')?.click();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);

  if (visible.length === 0) return null;

  return (
    <>
      <DropdownMenu>
        <Tooltip>
          <TooltipTrigger asChild>
            <DropdownMenuTrigger asChild>
              <Button id="quick-create-trigger" size="icon" variant="ghost" className="h-7 w-7 shrink-0">
                <Plus className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
          </TooltipTrigger>
          <TooltipContent side="bottom">Quick create (c)</TooltipContent>
        </Tooltip>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel className="text-xs text-muted-foreground">Create new</DropdownMenuLabel>
          <DropdownMenuSeparator />
          {visible.map((a) => {
            const Icon = a.icon;
            return (
              <DropdownMenuItem
                key={a.kind === 'dialog' ? `d:${a.key}` : `n:${a.href}`}
                onSelect={() => {
                  if (a.kind === 'dialog') setActive(a.key);
                  else navigate(a.href);
                }}
              >
                <Icon className="mr-2 h-4 w-4" /> {a.label}
              </DropdownMenuItem>
            );
          })}
        </DropdownMenuContent>
      </DropdownMenu>

      <CreateLeadDialog open={active === 'lead'} onOpenChange={(o) => !o && setActive(null)} />
      <CreateTaskDialog open={active === 'task'} onOpenChange={(o) => !o && setActive(null)} />
      <CreateTicketDialog hideTrigger open={active === 'ticket'} onOpenChange={(o) => !o && setActive(null)} />
    </>
  );
}
