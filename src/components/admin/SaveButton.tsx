import { Loader2, Save } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

interface SaveButtonProps {
  onClick: () => void;
  /** True while the mutation is in flight. */
  isPending?: boolean;
  /** True when there are unsaved edits — renders the dirty dot. */
  hasChanges?: boolean;
  /** Defaults to "Save changes" — the platform-wide wording. */
  label?: string;
  size?: 'default' | 'sm';
  disabled?: boolean;
  className?: string;
}

/**
 * The canonical Save control. Always top-right in `<AdminPageHeader />` —
 * never a second save button further down the page.
 */
export function SaveButton({
  onClick,
  isPending = false,
  hasChanges = false,
  label = 'Save changes',
  size = 'default',
  disabled,
  className,
}: SaveButtonProps) {
  return (
    <Button
      onClick={onClick}
      size={size}
      disabled={disabled ?? isPending}
      className={cn('relative', className)}
    >
      {hasChanges && !isPending && (
        <span
          aria-hidden
          className="absolute -top-1 -right-1 h-3 w-3 rounded-full bg-destructive"
        />
      )}
      {isPending ? (
        <Loader2 className="h-4 w-4 mr-2 animate-spin" />
      ) : (
        <Save className="h-4 w-4 mr-2" />
      )}
      {label}
    </Button>
  );
}
