import { describe, it, expect } from 'vitest';
import { isRouteAllowed, findNavMatch } from '../admin-route-access';
import type { AppRole } from '@/types/cms';

/**
 * A salesperson typed /admin/settings and got the page. The sidebar hid the
 * link — nothing guarded the route. Hiding is not gating. The guard resolves
 * routes against the SAME navigationGroups the sidebar renders from, so
 * these tests run against the real navigation data: if someone moves Site
 * Settings out of an admin-only group, this suite says so.
 */

const salesAccess = {
  isAdmin: false,
  roles: ['sales'] as AppRole[],
  accessMap: { sales: new Set(['deals', 'quotes', 'contracts', 'blog']) } as never,
};

describe('admin-only surfaces are gated, not just hidden', () => {
  it.each(['/admin/settings', '/admin/branding', '/admin/users', '/admin/roles', '/admin/modules'])(
    'sales is denied %s',
    (path) => {
      expect(isRouteAllowed(path, salesAccess)).toBe(false);
    },
  );

  it('admin passes everything', () => {
    expect(isRouteAllowed('/admin/settings', { ...salesAccess, isAdmin: true })).toBe(true);
  });
});

describe('granted modules stay reachable', () => {
  it('sales reaches the modules their roles grant', () => {
    expect(isRouteAllowed('/admin/deals', salesAccess)).toBe(true);
  });

  it('documents the quotes/invoicing vocabulary split', () => {
    // The Quotes nav item is gated by moduleId 'invoicing', NOT 'quotes' —
    // so a matrix grant of 'quotes' does not open /admin/quotes. The sidebar
    // and the route guard share this reading (same source), so there is no
    // drift between them — but the matrix key and the nav key disagree, and
    // this test pins the current behaviour until that is deliberately fixed.
    expect(isRouteAllowed('/admin/quotes', salesAccess)).toBe(false);
    expect(isRouteAllowed('/admin/quotes', {
      ...salesAccess,
      accessMap: { sales: new Set(['invoicing']) } as never,
    })).toBe(true);
  });

  it('sales is denied modules outside the grant', () => {
    // Accounting is a nav item with a moduleId not in the sales grant.
    expect(isRouteAllowed('/admin/accounting', salesAccess)).toBe(false);
  });

  it('sub-paths inherit the parent item verdict', () => {
    expect(isRouteAllowed('/admin/users/login-activity', salesAccess)).toBe(false);
  });

  it('the dashboard stays open to any staff role', () => {
    expect(isRouteAllowed('/admin', salesAccess)).toBe(true);
  });
});

describe('resolution mechanics', () => {
  it('longest href wins, not first hit', () => {
    const m = findNavMatch('/admin/users/login-activity');
    expect(m?.item.href).toBe('/admin/users');
  });

  it('paths unknown to the nav are left to the page\'s own guard', () => {
    expect(isRouteAllowed('/admin/some-detail-page/42', salesAccess)).toBe(true);
  });

  it('an empty access map fails closed for module items', () => {
    expect(isRouteAllowed('/admin/deals', { ...salesAccess, accessMap: undefined })).toBe(false);
  });
});
