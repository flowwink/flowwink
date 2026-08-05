import { useState, useCallback, useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/hooks/useAuth';
import {
  DEFAULT_WIDGET_ORDER,
  buildPresetLayout,
  presetKeyForRoles,
  isWidgetRoleRelevant,
} from '@/lib/dashboard-presets';
import type { AppRole } from '@/types/cms';

export interface DashboardWidgetConfig {
  id: string;
  visible: boolean;
}

export interface DashboardLayout {
  widgets: DashboardWidgetConfig[];
}

const STORAGE_KEY = 'flowwink-dashboard-layout';

function getStorageKey(userId: string, presetKey: string) {
  // Preset key is part of the storage key so a role-preview switch shows the
  // previewed role's dashboard instead of the admin's saved layout.
  return `${STORAGE_KEY}-${userId}-${presetKey}`;
}

function mergeWithCatalog(stored: DashboardLayout): DashboardLayout {
  const existing = new Set(stored.widgets.map((w) => w.id));
  return {
    widgets: [
      ...stored.widgets.filter((w) => DEFAULT_WIDGET_ORDER.includes(w.id)),
      ...DEFAULT_WIDGET_ORDER.filter((id) => !existing.has(id)).map((id) => ({ id, visible: true })),
    ],
  };
}

/** Local read — instant paint; the DB row wins once it arrives. */
function loadLocal(userId: string, presetKey: AppRole | 'admin'): DashboardLayout {
  try {
    const raw = localStorage.getItem(getStorageKey(userId, presetKey));
    if (raw) return mergeWithCatalog(JSON.parse(raw) as DashboardLayout);
  } catch (_e) { /* ignore */ }
  return { widgets: buildPresetLayout(presetKey) };
}

/**
 * Dashboard layout, persisted per user AND per role preset.
 *
 * Storage is two-tier on purpose: `localStorage` for a flicker-free first
 * paint, `user_dashboard_layouts` as the source of truth so the layout follows
 * the user to another browser or device. Writes go to both; the DB write is
 * fire-and-forget so a slow network never blocks a toggle.
 */
export function useDashboardLayout() {
  const { profile, roles, isAdmin } = useAuth();
  const userId = profile?.id || 'anonymous';
  const presetKey = presetKeyForRoles(roles ?? [], isAdmin);
  const isAuthed = !!profile?.id;

  const [layout, setLayout] = useState<DashboardLayout>(() => loadLocal(userId, presetKey));
  const [isSynced, setIsSynced] = useState(false);
  const dirtyRef = useRef(false);

  // Local re-read whenever the identity/preset changes.
  useEffect(() => {
    dirtyRef.current = false;
    setIsSynced(false);
    setLayout(loadLocal(userId, presetKey));
  }, [userId, presetKey]);

  // Remote hydrate. Skipped for anonymous; a local edit made before the
  // response lands is never overwritten (dirtyRef).
  useEffect(() => {
    if (!isAuthed) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from('user_dashboard_layouts')
        .select('widgets')
        .eq('user_id', profile!.id)
        .eq('preset_key', presetKey)
        .maybeSingle();
      if (cancelled || dirtyRef.current) return;
      const widgets = data?.widgets as unknown as DashboardWidgetConfig[] | undefined;
      if (Array.isArray(widgets) && widgets.length > 0) {
        const merged = mergeWithCatalog({ widgets });
        setLayout(merged);
        try {
          localStorage.setItem(getStorageKey(userId, presetKey), JSON.stringify(merged));
        } catch (_e) { /* ignore */ }
      }
      setIsSynced(true);
    })();
    return () => { cancelled = true; };
  }, [isAuthed, profile, presetKey, userId]);

  const persist = useCallback((next: DashboardLayout) => {
    dirtyRef.current = true;
    try {
      localStorage.setItem(getStorageKey(userId, presetKey), JSON.stringify(next));
    } catch (_e) { /* ignore */ }
    if (!isAuthed) return;
    void supabase
      .from('user_dashboard_layouts')
      .upsert(
        { user_id: profile!.id, preset_key: presetKey, widgets: next.widgets as never },
        { onConflict: 'user_id,preset_key' },
      );
  }, [userId, presetKey, isAuthed, profile]);

  const saveLayout = useCallback((newLayout: DashboardLayout) => {
    setLayout(newLayout);
    persist(newLayout);
  }, [persist]);

  const toggleWidget = useCallback((widgetId: string) => {
    setLayout((prev) => {
      const updated = {
        widgets: prev.widgets.map((w) =>
          w.id === widgetId ? { ...w, visible: !w.visible } : w,
        ),
      };
      persist(updated);
      return updated;
    });
  }, [persist]);

  const reorderWidgets = useCallback((fromIndex: number, toIndex: number) => {
    setLayout((prev) => {
      const widgets = [...prev.widgets];
      const [moved] = widgets.splice(fromIndex, 1);
      widgets.splice(toIndex, 0, moved);
      const updated = { widgets };
      persist(updated);
      return updated;
    });
  }, [persist]);

  const resetLayout = useCallback(() => {
    const preset = { widgets: buildPresetLayout(presetKey) };
    setLayout(preset);
    dirtyRef.current = true;
    try {
      localStorage.removeItem(getStorageKey(userId, presetKey));
    } catch (_e) { /* ignore */ }
    if (isAuthed) {
      void supabase
        .from('user_dashboard_layouts')
        .delete()
        .eq('user_id', profile!.id)
        .eq('preset_key', presetKey);
    }
  }, [userId, presetKey, isAuthed, profile]);

  /** Apply another role's preset without changing the user's roles. */
  const applyPreset = useCallback((key: AppRole | 'admin') => {
    saveLayout({ widgets: buildPresetLayout(key) });
  }, [saveLayout]);

  const isWidgetVisible = useCallback((widgetId: string) => {
    if (!isWidgetRoleRelevant(widgetId, roles ?? [], isAdmin)) return false;
    return layout.widgets.find((w) => w.id === widgetId)?.visible ?? true;
  }, [layout, roles, isAdmin]);

  const getWidgetOrder = useCallback(() => layout.widgets.map((w) => w.id), [layout]);

  return {
    layout,
    presetKey,
    isSynced,
    applyPreset,
    toggleWidget,
    reorderWidgets,
    resetLayout,
    isWidgetVisible,
    getWidgetOrder,
    saveLayout,
  };
}
