import { Link } from 'react-router-dom';
import { ArrowRight } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';

/**
 * Shared chrome for the module dashboard widgets: a titled card with an
 * optional "open module" link and a tile grid. Keeps every widget visually
 * identical so the dashboard reads as one surface, not a pile of cards.
 */
export function WidgetShell({
  title,
  icon: Icon,
  href,
  linkLabel = 'Open',
  isLoading,
  tileCount = 3,
  children,
}: {
  title: string;
  icon: React.ComponentType<{ className?: string }>;
  href?: string;
  linkLabel?: string;
  isLoading?: boolean;
  tileCount?: number;
  children: React.ReactNode;
}) {
  return (
    <Card>
      <CardHeader className="pb-3 flex-row items-center justify-between space-y-0">
        <CardTitle className="text-base font-medium flex items-center gap-2">
          <Icon className="h-4 w-4 text-primary" />
          {title}
        </CardTitle>
        {href && (
          <Link
            to={href}
            className="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1"
          >
            {linkLabel}
            <ArrowRight className="h-3 w-3" />
          </Link>
        )}
      </CardHeader>
      <CardContent className="pt-0">
        {isLoading ? (
          <div className={`grid grid-cols-${tileCount} gap-3`}>
            {[...Array(tileCount)].map((_, i) => (
              <Skeleton key={i} className="h-16 w-full" />
            ))}
          </div>
        ) : (
          children
        )}
      </CardContent>
    </Card>
  );
}

export type TileTone = 'default' | 'warning' | 'destructive' | 'success';

const TONE_CLASS: Record<TileTone, string> = {
  default: 'text-foreground',
  warning: 'text-warning',
  destructive: 'text-destructive',
  success: 'text-success',
};

export function MetricTile({
  label,
  value,
  tone = 'default',
  href,
}: {
  label: string;
  value: string | number;
  tone?: TileTone;
  href?: string;
}) {
  const body = (
    <div className="rounded-lg border p-3 h-full transition-colors hover:bg-muted/50">
      <p className={`text-xl font-semibold tabular-nums ${TONE_CLASS[tone]}`}>{value}</p>
      <p className="text-xs text-muted-foreground mt-0.5">{label}</p>
    </div>
  );
  return href ? (
    <Link to={href} className="block">
      {body}
    </Link>
  ) : (
    body
  );
}
