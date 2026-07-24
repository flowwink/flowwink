import { useState, useEffect, useMemo, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  Search,
  Building2,
  UserPlus,
  HandCoins,
  ShoppingCart,
  FileText,
  FileSignature,
  LifeBuoy,
  ScrollText,
  FolderOpen,
  BookOpen,
  Package,
  FileCode,
  Newspaper,
  User,
  Truck,
  Briefcase,
  Receipt,
  CalendarPlus,
  Megaphone,
  ClipboardList,
  Clock,
  Image as ImageIcon,
  History,
  Lightbulb,
  ArrowRight,
} from 'lucide-react';
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
} from '@/components/ui/command';
import { Badge } from '@/components/ui/badge';
import { useAuth } from '@/hooks/useAuth';
import { useModules } from '@/hooks/useModules';
import { useNavFeatureFlags, isFeatureFlagOn } from '@/hooks/useNavFeatureFlags';
import { navigationGroups } from './adminNavigation';
import { supabase } from '@/integrations/supabase/client';
import type { AppRole } from '@/types/cms';

const RECENT_KEY = 'admin-search-recent';
const MAX_RECENT = 5;

const ENTITY_META: Record<string, { label: string; icon: any; group: string }> = {
  company:    { label: 'Company',    icon: Building2,     group: 'Companies' },
  lead:       { label: 'Lead',       icon: UserPlus,      group: 'Leads' },
  deal:       { label: 'Deal',       icon: HandCoins,     group: 'Deals' },
  order:      { label: 'Order',      icon: ShoppingCart,  group: 'Orders' },
  invoice:    { label: 'Invoice',    icon: FileText,      group: 'Invoices' },
  quote:      { label: 'Quote',      icon: FileSignature, group: 'Quotes' },
  ticket:     { label: 'Ticket',     icon: LifeBuoy,      group: 'Tickets' },
  contract:   { label: 'Contract',   icon: ScrollText,    group: 'Contracts' },
  document:   { label: 'Document',   icon: FolderOpen,    group: 'Documents' },
  kb_article: { label: 'KB',         icon: BookOpen,      group: 'Knowledge' },
  product:    { label: 'Product',    icon: Package,       group: 'Products' },
  page:       { label: 'Page',       icon: FileCode,      group: 'Pages' },
  blog_post:  { label: 'Blog post',  icon: Newspaper,     group: 'Blog' },
  employee:   { label: 'Employee',   icon: User,          group: 'Employees' },
  vendor:     { label: 'Vendor',     icon: Truck,         group: 'Vendors' },
  project:    { label: 'Project',    icon: Briefcase,     group: 'Projects' },
};

interface QuickAction {
  label: string;
  href: string;
  icon: any;
  moduleId?: string;
  roles: AppRole[]; // admin sees all
}

// Role-aware quick creates surfaced at the top of ⌘K. Filtered by user roles + enabled modules.
const QUICK_ACTIONS: QuickAction[] = [
  // Sales
  { label: 'New lead',            href: '/admin/leads?new=1',           icon: UserPlus,      moduleId: 'leads',       roles: ['sales', 'marketing'] },
  { label: 'New deal',            href: '/admin/deals?new=1',           icon: HandCoins,     moduleId: 'deals',       roles: ['sales'] },
  { label: 'New quote',           href: '/admin/quotes?new=1',            icon: FileSignature, moduleId: 'quotes',      roles: ['sales'] },
  { label: 'New company',         href: '/admin/companies?new=1',       icon: Building2,     moduleId: 'companies',   roles: ['sales', 'accounting', 'support'] },
  // Accounting / CFO
  { label: 'New invoice',         href: '/admin/invoices?new=1',          icon: FileText,      moduleId: 'invoicing',   roles: ['accounting', 'sales'] },
  { label: 'New expense',         href: '/admin/expenses?new=1',        icon: Receipt,       moduleId: 'expenses',    roles: ['accounting', 'hr'] },
  { label: 'New purchase order',  href: '/admin/purchase-orders?new=1', icon: ClipboardList, moduleId: 'purchasing',  roles: ['purchasing', 'accounting'] },
  // Support
  { label: 'New ticket',          href: '/admin/tickets?new=1',         icon: LifeBuoy,      moduleId: 'tickets',     roles: ['support'] },
  // HR
  { label: 'New employee',        href: '/admin/hr?new=1',       icon: User,          moduleId: 'hr',          roles: ['hr'] },
  { label: 'New job posting',     href: '/admin/recruitment?new=1',     icon: Briefcase,     moduleId: 'recruitment', roles: ['hr'] },
  // Marketing / content
  { label: 'New blog post',       href: '/admin/blog/new',              icon: Newspaper,     moduleId: 'blog',        roles: ['marketing'] },
  { label: 'New page',            href: '/admin/pages/new',             icon: FileCode,      moduleId: 'pages',       roles: ['marketing'] },
  { label: 'New campaign',        href: '/admin/campaigns?new=1',       icon: Megaphone,     moduleId: 'paidGrowth',  roles: ['marketing'] },
  { label: 'New media upload',    href: '/admin/media?upload=1',      icon: ImageIcon,     moduleId: 'media',       roles: ['marketing'] },
  // Projects
  { label: 'New project',         href: '/admin/projects?new=1',        icon: Briefcase,     moduleId: 'projects',    roles: ['projects'] },
  { label: 'New task',            href: '/admin/projects?new=task',           icon: CalendarPlus,  moduleId: 'projects',    roles: ['projects', 'sales', 'support'] },
  { label: 'New time entry',      href: '/admin/timesheets?tab=entries&new=1', icon: Clock,      moduleId: 'projects',    roles: ['projects', 'hr', 'sales'] },
  // Warehouse / purchasing
  { label: 'New product',         href: '/admin/products?new=1',        icon: Package,       moduleId: 'ecommerce',   roles: ['warehouse', 'sales'] },
  { label: 'New vendor',          href: '/admin/vendors?new=1',         icon: Truck,         moduleId: 'purchasing',  roles: ['purchasing', 'warehouse'] },
  // Accounting
  { label: 'New journal entry',   href: '/admin/accounting?tab=journal&new=1', icon: BookOpen,   moduleId: 'accounting',  roles: ['accounting'] },
];

interface SearchHit {
  entity_type: string;
  entity_id: string;
  title: string;
  subtitle: string | null;
  url: string;
  rank: number;
}

interface RecentItem {
  href: string;
  title: string;
  subtitle: string | null;
  type: 'page' | 'entity' | 'create';
}

function readRecent(): RecentItem[] {
  try {
    const raw = localStorage.getItem(RECENT_KEY);
    return raw ? (JSON.parse(raw) as RecentItem[]) : [];
  } catch {
    return [];
  }
}

function writeRecent(item: RecentItem) {
  try {
    const existing = readRecent().filter((r) => r.href !== item.href);
    const next = [item, ...existing].slice(0, MAX_RECENT);
    localStorage.setItem(RECENT_KEY, JSON.stringify(next));
  } catch {
    // ignore storage errors
  }
}

function useDebounced<T>(value: T, ms = 200): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setV(value), ms);
    return () => clearTimeout(id);
  }, [value, ms]);
  return v;
}

export function useAdminSearch() {
  const [searchOpen, setSearchOpen] = useState(false);

  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === 'k' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        setSearchOpen((open) => !open);
      }
    };
    document.addEventListener('keydown', down);
    return () => document.removeEventListener('keydown', down);
  }, []);

  return { searchOpen, setSearchOpen };
}

interface AdminSearchCommandProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function AdminSearchCommand({ open, onOpenChange }: AdminSearchCommandProps) {
  const navigate = useNavigate();
  const { isAdmin, roles } = useAuth();
  const { data: modules } = useModules();
  const { data: featureFlags } = useNavFeatureFlags();
  const [query, setQuery] = useState('');
  const debouncedQuery = useDebounced(query, 200);

  useEffect(() => {
    if (!open) setQuery('');
  }, [open]);

  const roleFilteredGroups = navigationGroups.filter(
    (group) => !group.adminOnly || isAdmin
  );

  const filteredGroups = useMemo(
    () =>
      roleFilteredGroups
        .map((group) => ({
          ...group,
          items: group.items.filter((item) => {
            if (item.moduleId) {
              if (!modules) return true;
              if (!(modules[item.moduleId]?.enabled ?? true)) return false;
            }
            if (!isFeatureFlagOn(featureFlags, item.featureFlag)) return false;
            return true;
          }),
        }))
        .filter((group) => group.items.length > 0),
    [roleFilteredGroups, modules, featureFlags]
  );

  const quickActions = useMemo(() => {
    return QUICK_ACTIONS.filter((a) => {
      if (a.moduleId && modules && !(modules[a.moduleId]?.enabled ?? true)) return false;
      if (isAdmin) return true;
      return a.roles.some((r) => roles.includes(r));
    });
  }, [modules, isAdmin, roles]);

  const { data: hits, isFetching } = useQuery({
    queryKey: ['global-search', debouncedQuery],
    enabled: isAdmin && open && debouncedQuery.trim().length >= 2,
    queryFn: async (): Promise<SearchHit[]> => {
      const { data, error } = await supabase.rpc('global_search' as any, {
        search_query: debouncedQuery,
        result_limit: 6,
      });
      if (error) throw error;
      return (data ?? []) as SearchHit[];
    },
    staleTime: 10_000,
  });

  const hitsByGroup = useMemo(() => {
    const map = new Map<string, SearchHit[]>();
    for (const h of hits ?? []) {
      const key = ENTITY_META[h.entity_type]?.group ?? h.entity_type;
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(h);
    }
    return Array.from(map.entries());
  }, [hits]);

  const [recent, setRecent] = useState<RecentItem[]>(() => readRecent());

  useEffect(() => {
    if (open) setRecent(readRecent());
  }, [open]);

  const handleSelect = useCallback(
    (href: string, title: string, type: RecentItem['type'], subtitle: string | null = null) => {
      writeRecent({ href, title, subtitle, type });
      onOpenChange(false);
      navigate(href);
    },
    [navigate, onOpenChange]
  );

  const showingDataResults = debouncedQuery.trim().length >= 2;
  const hasResults = hitsByGroup.length > 0;
  const showRecent = !showingDataResults && recent.length > 0;

  return (
    <CommandDialog open={open} onOpenChange={onOpenChange}>
      <CommandInput
        placeholder="Search pages, leads, orders, invoices, contracts…"
        value={query}
        onValueChange={setQuery}
      />
      <CommandList>
        <CommandEmpty>
          {isFetching ? (
            'Searching…'
          ) : (
            <div className="flex flex-col items-center justify-center gap-2 py-6 text-center">
              <p className="text-sm font-medium">No results found</p>
              <p className="text-xs text-muted-foreground max-w-[260px]">
                Try a different keyword, or jump to one of the common actions below.
              </p>
              {quickActions.length > 0 && (
                <div className="flex flex-wrap justify-center gap-2 mt-2">
                  {quickActions.slice(0, 4).map((a) => (
                    <button
                      key={a.href}
                      onClick={() => handleSelect(a.href, a.label, 'create')}
                      className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs hover:bg-accent transition-colors"
                    >
                      <a.icon className="h-3 w-3" />
                      {a.label}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </CommandEmpty>

        {showRecent && (
          <CommandGroup heading="Recent">
            {recent.map((item) => {
              const Icon =
                quickActions.find((a) => a.href === item.href)?.icon ??
                (item.type === 'entity' ? FileText : ArrowRight);
              return (
                <CommandItem
                  key={item.href}
                  value={`recent ${item.title} ${item.href}`}
                  onSelect={() => handleSelect(item.href, item.title, item.type, item.subtitle)}
                  className="cursor-pointer"
                >
                  <History className="mr-2 h-4 w-4 shrink-0 text-muted-foreground" />
                  <div className="flex flex-col min-w-0">
                    <span className="truncate">{item.title}</span>
                    {item.subtitle && (
                      <span className="text-xs text-muted-foreground truncate">
                        {item.subtitle}
                      </span>
                    )}
                  </div>
                  <Icon className="ml-auto h-3.5 w-3.5 text-muted-foreground" />
                </CommandItem>
              );
            })}
          </CommandGroup>
        )}

        {showRecent && <CommandSeparator />}

        {quickActions.length > 0 && (
          <CommandGroup heading="Quick create">
            {quickActions.map((a) => (
              <CommandItem
                key={a.href}
                value={`create new ${a.label}`}
                onSelect={() => handleSelect(a.href, a.label, 'create')}
                className="cursor-pointer"
              >
                <a.icon className="mr-2 h-4 w-4" />
                <span>{a.label}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        )}

        {quickActions.length > 0 && <CommandSeparator />}

        {showingDataResults && hasResults &&
          hitsByGroup.map(([group, items]) => (
            <CommandGroup key={`hit-${group}`} heading={group}>
              {items.map((hit) => {
                const meta = ENTITY_META[hit.entity_type];
                const Icon = meta?.icon ?? FileText;
                return (
                  <CommandItem
                    key={`${hit.entity_type}-${hit.entity_id}`}
                    value={`${hit.entity_type} ${hit.title} ${hit.subtitle ?? ''} ${hit.entity_id}`}
                    onSelect={() =>
                      handleSelect(hit.url, hit.title, 'entity', hit.subtitle)
                    }
                    className="cursor-pointer"
                  >
                    <Icon className="mr-2 h-4 w-4 shrink-0" />
                    <div className="flex flex-col min-w-0 flex-1">
                      <span className="truncate">{hit.title || '(untitled)'}</span>
                      {hit.subtitle && (
                        <span className="text-xs text-muted-foreground truncate">
                          {hit.subtitle}
                        </span>
                      )}
                    </div>
                    <Badge variant="outline" className="ml-2 text-[10px] font-normal shrink-0">
                      {meta?.label ?? hit.entity_type}
                    </Badge>
                  </CommandItem>
                );
              })}
            </CommandGroup>
          ))}

        {showingDataResults && hasResults && <CommandSeparator />}

        {!showingDataResults && (
          <CommandGroup heading="Suggestions">
            <CommandItem
              value="suggestion open tickets"
              onSelect={() => handleSelect('/admin/tickets', 'Tickets', 'page')}
              className="cursor-pointer"
            >
              <Lightbulb className="mr-2 h-4 w-4 text-muted-foreground" />
              <span>Open tickets</span>
            </CommandItem>
            <CommandItem
              value="suggestion new lead"
              onSelect={() => handleSelect('/admin/leads?new=1', 'New lead', 'create')}
              className="cursor-pointer"
            >
              <Lightbulb className="mr-2 h-4 w-4 text-muted-foreground" />
              <span>Create a lead</span>
            </CommandItem>
            <CommandItem
              value="suggestion invoices"
              onSelect={() => handleSelect('/admin/invoices', 'Invoices', 'page')}
              className="cursor-pointer"
            >
              <Lightbulb className="mr-2 h-4 w-4 text-muted-foreground" />
              <span>Latest invoices</span>
            </CommandItem>
          </CommandGroup>
        )}

        {!showingDataResults && <CommandSeparator />}

        {filteredGroups.map((group) => (
          <CommandGroup key={group.label} heading={group.label}>
            {group.items.map((item) => (
              <CommandItem
                key={item.href}
                value={`page ${item.name} ${group.label}`}
                onSelect={() => handleSelect(item.href, item.name, 'page')}
                className="cursor-pointer"
              >
                <item.icon className="mr-2 h-4 w-4" />
                <span>{item.name}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        ))}
      </CommandList>
    </CommandDialog>
  );
}

interface SearchButtonProps {
  onClick: () => void;
  collapsed?: boolean;
}

export function SearchButton({ onClick, collapsed }: SearchButtonProps) {
  return (
    <div className="px-2 pt-1.5 pb-0.5">
      <button
        onClick={onClick}
        className="flex items-center gap-2 w-full px-2 py-1.5 text-sm text-sidebar-foreground/60 hover:text-sidebar-foreground hover:bg-sidebar-accent rounded-md transition-colors"
      >
        <Search className="h-4 w-4" />
        {!collapsed && (
          <>
            <span className="flex-1 text-left">Search...</span>
            <kbd className="hidden lg:inline-flex h-5 items-center gap-1 rounded border bg-muted px-1.5 font-mono text-[10px] font-medium text-muted-foreground">
              ⌘K
            </kbd>
          </>
        )}
      </button>
    </div>
  );
}
