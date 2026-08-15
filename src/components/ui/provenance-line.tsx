import type { ReactNode } from 'react';
import type { LucideIcon } from 'lucide-react';
import { Link } from 'react-router-dom';
import { cn } from '@/lib/utils';

/**
 * The provenance line — pattern 1 of the transparency design language (#97).
 *
 * One quiet line that says where a piece of content came from, what grounds
 * it, or why a state is what it is: "Read from acme.com on 14 Aug — distilled
 * by AI", "Grounded in 3 published sources". Pedagogy lives in the interface,
 * not in manuals — so the line is ALWAYS visible (never tooltip-only, never a
 * modal) and stays at one sentence. If you are tempted to write two, the
 * second belongs somewhere else.
 *
 * `to` + `linkLabel` render an optional trailing internal link — the
 * dependency-link pattern's little sibling ("Set the company's country").
 */
export function ProvenanceLine({
  icon: Icon,
  to,
  linkLabel,
  className,
  children,
}: {
  icon?: LucideIcon;
  to?: string;
  linkLabel?: string;
  className?: string;
  children: ReactNode;
}) {
  return (
    <p className={cn('text-xs text-muted-foreground flex items-start gap-1.5', className)}>
      {Icon && <Icon className="h-3 w-3 mt-0.5 shrink-0" aria-hidden />}
      <span>
        {children}
        {to && (
          <>
            {' '}
            <Link to={to} className="underline underline-offset-2 hover:text-foreground">
              {linkLabel ?? 'View'}
            </Link>
          </>
        )}
      </span>
    </p>
  );
}
