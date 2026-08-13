import { describe, expect, it } from 'vitest';
import { rolesWithModule } from '../ModuleRoleAccessSection';
import type { RoleModuleAccessMap } from '@/hooks/useRoleModuleAccess';
import type { AppRole } from '@/types/cms';

/**
 * The transparency panel's core claim is the inversion: the matrix is stored
 * role → modules, the panel answers module → roles. If the inversion lies, the
 * panel teaches operators the wrong mental model of the ONE dial that now
 * governs sidebar, routes and RLS alike.
 */
describe('rolesWithModule', () => {
  const map: RoleModuleAccessMap = {
    sales: new Set(['leads', 'wiki']),
    hr: new Set(['wiki']),
    support: new Set(['tickets']),
  } as RoleModuleAccessMap;

  it('inverts the matrix correctly', () => {
    expect(rolesWithModule(map, 'wiki')).toEqual(['sales', 'hr'] as AppRole[]);
    expect(rolesWithModule(map, 'leads')).toEqual(['sales'] as AppRole[]);
  });

  it('zero grants is an answer, not an absence', () => {
    // wiki/kb/docs shipped granted to no role and nothing said so — the panel
    // exists to make exactly this state loud. Empty array must be reachable.
    expect(rolesWithModule(map, 'pos')).toEqual([]);
    expect(rolesWithModule(undefined, 'pos')).toEqual([]);
  });
});
