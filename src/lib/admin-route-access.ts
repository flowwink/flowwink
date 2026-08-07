/**
 * Route-level access for /admin pages — same source of truth as the sidebar.
 *
 * The sidebar HID pages the user's roles did not grant, but nothing guarded
 * the ROUTES: a salesperson could type /admin/settings and get the page.
 * Hiding is not gating. This resolves a pathname against the same
 * navigationGroups the sidebar renders from, so the two surfaces cannot
 * disagree: if the sidebar would not show the link, the route does not serve
 * the page.
 *
 * Resolution: longest matching href wins (so /admin/users/login-activity
 * matches the Users item, not the dashboard). A pathname that matches no nav
 * item is left to the page's own guard — several admin pages carry one, and
 * failing closed on unknown paths would break deep-links like detail pages
 * whose list page is granted.
 */
import { navigationGroups, type NavGroup, type NavItem } from '@/components/admin/adminNavigation';
import type { AppRole } from '@/types/cms';

export interface RouteAccessInput {
  isAdmin: boolean;
  roles: AppRole[];
  /** role → Set of granted moduleIds, from role_module_access. */
  accessMap: Partial<Record<AppRole, Set<string>>> | undefined;
}

interface Match {
  group: NavGroup;
  item: NavItem;
}

export function findNavMatch(pathname: string): Match | null {
  let best: Match | null = null;
  let bestLen = 0;
  for (const group of navigationGroups) {
    for (const item of group.items) {
      const href = item.href;
      const hit =
        pathname === href ||
        (href !== '/admin' && pathname.startsWith(href + '/')) ||
        (href !== '/admin' && pathname === href);
      if (hit && href.length > bestLen) {
        best = { group, item };
        bestLen = href.length;
      }
    }
  }
  return best;
}

export function isRouteAllowed(pathname: string, input: RouteAccessInput): boolean {
  if (input.isAdmin) return true;

  const match = findNavMatch(pathname);
  if (!match) return true; // unknown to nav → the page's own guard decides

  const { group, item } = match;

  // Same rules, same order, as the sidebar's item filter.
  if (group.adminOnly) return false;

  if (item.moduleId) {
    const allowed = new Set<string>();
    input.roles.forEach((r) => {
      const set = input.accessMap?.[r];
      if (set) set.forEach((id) => allowed.add(id));
    });
    return allowed.has(item.moduleId);
  }

  if (group.allowedRoles && group.allowedRoles.length > 0) {
    return input.roles.some((r) => group.allowedRoles!.includes(r));
  }
  if (item.allowedRoles && item.allowedRoles.length > 0) {
    return input.roles.some((r) => item.allowedRoles!.includes(r));
  }
  return true;
}
