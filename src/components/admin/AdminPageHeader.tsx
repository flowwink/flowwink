import { ReactNode } from 'react';
import { ArrowLeft, MoreHorizontal } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

interface BackAction {
  label: string;
  onClick: () => void;
}

interface AdminPageHeaderProps {
  title: string;
  description?: string;
  /**
   * Optional lucide icon component rendered next to the title.
   * Pass the component itself (e.g. `icon={Truck}`), not an element.
   */
  icon?: React.ComponentType<{ className?: string }>;
  /** Primary actions on the right (max 2 — everything else goes in `secondaryActions`). */
  children?: ReactNode;
  /**
   * Less essential actions (exports, audits, danger zone, docs links).
   * Rendered inside an overflow "…" menu so the header stays calm.
   * Wrap each item in `<DropdownMenuItem>`.
   */
  secondaryActions?: ReactNode;
  backAction?: BackAction;
  className?: string;
}

/**
 * The single canonical page header for every admin page.
 *
 * Design system rules (see docs/reference/design-system.md):
 * - One `<h1>` per page, and it lives here — never hand-rolled.
 * - Primary action sits top-right; the Save action uses `<SaveButton />`.
 * - Secondary/rare actions collapse into the overflow menu.
 */
export function AdminPageHeader({
  title,
  description,
  icon: Icon,
  children,
  secondaryActions,
  backAction,
  className,
}: AdminPageHeaderProps) {
  return (
    <div className={cn('mb-8', className)}>
      {backAction && (
        <Button
          variant="ghost"
          size="sm"
          onClick={backAction.onClick}
          className="mb-4 -ml-2 text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4 mr-1" />
          {backAction.label}
        </Button>
      )}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h1 className="font-serif text-2xl font-bold text-foreground flex items-center gap-2">
            {Icon && <Icon className="h-6 w-6 shrink-0 text-muted-foreground" />}
            <span className="truncate">{title}</span>
          </h1>
          {description && (
            <p className="text-sm text-muted-foreground mt-1 max-w-2xl">{description}</p>
          )}
        </div>
        {(children || secondaryActions) && (
          <div className="flex items-center gap-2 shrink-0">
            {children}
            {secondaryActions && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" aria-label="More actions">
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-56">
                  {secondaryActions}
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
