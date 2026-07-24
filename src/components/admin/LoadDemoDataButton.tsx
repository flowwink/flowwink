import { useState } from 'react';
import { Sparkles, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { useQueryClient } from '@tanstack/react-query';
import { getSeederForModule } from '@/lib/module-demo-seed';
import type { ModulesSettings } from '@/hooks/useModules';

interface LoadDemoDataButtonProps {
  /** ModulesSettings key (e.g. 'leads', 'deals', 'tickets'). */
  moduleId: keyof ModulesSettings;
  /** Query keys to invalidate after seeding. */
  invalidateKeys?: readonly (readonly unknown[])[];
  variant?: 'default' | 'outline' | 'secondary';
  size?: 'default' | 'sm' | 'lg';
  label?: string;
}

/**
 * Drop-in button that calls `seed_module_demo` for a given module and
 * refreshes the caller's list. Rendered only when a seeder is registered
 * for the module in `MODULE_DEMO_SEEDERS`.
 */
export function LoadDemoDataButton({
  moduleId,
  invalidateKeys = [],
  variant = 'outline',
  size = 'sm',
  label = 'Load demo data',
}: LoadDemoDataButtonProps) {
  const [loading, setLoading] = useState(false);
  const queryClient = useQueryClient();
  const seederName = getSeederForModule(moduleId);

  if (!seederName) return null;

  const handleClick = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('seed_module_demo' as any, {
        p_module: seederName,
        p_scenario: 'default',
      });
      if (error) throw error;
      const detail =
        (data as { result?: Record<string, unknown>; detail?: Record<string, unknown> } | null)
          ?.result ??
        (data as { detail?: Record<string, unknown> } | null)?.detail ??
        {};
      const inserted = Object.values(detail).reduce(
        (sum: number, v) => (typeof v === 'number' ? sum + v : sum),
        0,
      );
      toast.success(
        inserted > 0
          ? `Seeded ${inserted} demo ${seederName} row(s)`
          : `Seeded demo data for ${seederName}`,
        { description: 'Remove from /admin/modules → Reset.' },
      );
      queryClient.invalidateQueries({ queryKey: ['module-seed-counts'] });
      for (const key of invalidateKeys) {
        queryClient.invalidateQueries({ queryKey: key as unknown[] });
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Seeding failed';
      toast.error(msg);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Button variant={variant} size={size} onClick={handleClick} disabled={loading}>
      {loading ? (
        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
      ) : (
        <Sparkles className="mr-2 h-4 w-4" />
      )}
      {label}
    </Button>
  );
}
