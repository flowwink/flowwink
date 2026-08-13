import { Link } from 'react-router-dom';
import { AlertTriangle, Shield, ExternalLink } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { useRoleModuleAccess, type RoleModuleAccessMap } from '@/hooks/useRoleModuleAccess';
import { ROLE_LABELS, type AppRole } from '@/types/cms';

/**
 * Which roles a module is visible to — and, since matrix-RLS (2026-08-13),
 * whose data access it governs. One dial, so this panel can say "seen and
 * reached by" truthfully; before that migration the honest phrasing would have
 * been "seen by", with the data answering to a different system entirely.
 *
 * Exists because the opposite state was invisible: wiki, knowledge base and
 * docs shipped granted to NO role at all, and nothing anywhere said so — an
 * admin saw them fine (admin is implicit, never stored in the matrix) and had
 * no reason to suspect every other role saw nothing. Zero roles is therefore
 * rendered as a warning, not as an empty list.
 */

/** Roles granted a module, in ROLE_LABELS order. Exported for the guardrail test. */
export function rolesWithModule(map: RoleModuleAccessMap | undefined, moduleId: string): AppRole[] {
  if (!map) return [];
  return (Object.keys(ROLE_LABELS) as AppRole[]).filter((role) => map[role]?.has(moduleId));
}

export function ModuleRoleAccessSection({ moduleId }: { moduleId: string }) {
  const { data: accessMap, isLoading } = useRoleModuleAccess();

  if (isLoading) {
    return (
      <div className="space-y-2">
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-6 w-full" />
      </div>
    );
  }

  const roles = rolesWithModule(accessMap, moduleId);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-medium flex items-center gap-1.5">
          <Shield className="h-3.5 w-3.5" />
          Seen and reached by
        </h4>
        <Link
          to="/admin/roles"
          className="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1"
        >
          Edit in Role Permissions
          <ExternalLink className="h-3 w-3" />
        </Link>
      </div>

      {roles.length === 0 ? (
        <div className="flex items-start gap-2 rounded-md border border-warning/50 bg-warning/10 p-2.5 text-sm">
          <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5 text-warning" />
          <span>
            No role is granted this module — only administrators can see or use
            it. If that is not intended, grant it in Role Permissions.
          </span>
        </div>
      ) : (
        <div className="flex flex-wrap gap-1.5">
          {roles.map((role) => (
            <Badge key={role} variant="secondary">
              {ROLE_LABELS[role]}
            </Badge>
          ))}
          <Badge variant="outline" className="text-muted-foreground">
            Administrator (always)
          </Badge>
        </div>
      )}

      <p className="text-xs text-muted-foreground">
        Grants control the sidebar, page routes and row-level data access — one
        setting for all three. The module toggle above still decides whether the
        module exists on this site at all.
      </p>
    </div>
  );
}
