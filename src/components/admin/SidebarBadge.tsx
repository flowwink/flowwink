import { useOpenTicketCount } from '@/hooks/useTickets';
import { useNewLeadCount } from '@/hooks/useLeads';
import { useActiveDealCount } from '@/hooks/useDeals';
import { PendingApprovalsBadge } from './PendingApprovalsBadge';

const BADGE_HREFS = [
  '/admin/approvals',
  '/admin/tickets',
  '/admin/leads',
  '/admin/deals',
] as const;

type BadgeHref = (typeof BADGE_HREFS)[number];

function isBadgeHref(href: string): href is BadgeHref {
  return BADGE_HREFS.includes(href as BadgeHref);
}

function CountBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span className="ml-auto inline-flex items-center justify-center rounded-full bg-primary text-primary-foreground text-[10px] font-medium h-4 min-w-4 px-1">
      {count > 99 ? '99+' : count}
    </span>
  );
}

interface SidebarBadgeProps {
  href: string;
}

export function SidebarBadge({ href }: SidebarBadgeProps) {
  if (!isBadgeHref(href)) return null;

  if (href === '/admin/approvals') {
    return <PendingApprovalsBadge />;
  }

  if (href === '/admin/tickets') {
    return <TicketOpenBadge />;
  }

  if (href === '/admin/leads') {
    return <NewLeadBadge />;
  }

  if (href === '/admin/deals') {
    return <ActiveDealBadge />;
  }

  return null;
}

function TicketOpenBadge() {
  const { data: count = 0 } = useOpenTicketCount();
  return <CountBadge count={count} />;
}

function NewLeadBadge() {
  const { data: count = 0 } = useNewLeadCount();
  return <CountBadge count={count} />;
}

function ActiveDealBadge() {
  const { data: count = 0 } = useActiveDealCount();
  return <CountBadge count={count} />;
}
