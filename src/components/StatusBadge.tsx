import React from 'react';
import { cn } from '@/lib/utils';
import { PencilLine, Clock, CheckCircle2, Archive } from 'lucide-react';
import type { PageStatus } from '@/types/cms';
import { STATUS_LABELS } from '@/types/cms';

interface StatusBadgeProps {
  status: PageStatus;
  className?: string;
}

const STATUS_ICON_MAP: Record<PageStatus, React.ElementType> = {
  draft: PencilLine,
  reviewing: Clock,
  published: CheckCircle2,
  archived: Archive,
};

export const StatusBadge = React.forwardRef<HTMLSpanElement, StatusBadgeProps>(
  ({ status, className }, ref) => {
    const Icon = STATUS_ICON_MAP[status] ?? PencilLine;
    return (
      <span
        ref={ref}
        className={cn(
          'status-badge',
          {
            'status-draft': status === 'draft',
            'status-reviewing': status === 'reviewing',
            'status-published': status === 'published',
            'status-archived': status === 'archived',
          },
          className
        )}
      >
        <Icon className="h-3.5 w-3.5" aria-hidden />
        <span>{STATUS_LABELS[status]}</span>
      </span>
    );
  }
);

StatusBadge.displayName = 'StatusBadge';
