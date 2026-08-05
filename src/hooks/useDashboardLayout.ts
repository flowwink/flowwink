import { useState, useCallback, useEffect } from 'react';
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

function load(userId: string, presetKey: AppRole | 'admin'): DashboardLayout {
  try {
    const raw = localStorage.getItem(getStorageKey(userId, presetKey));
    if (raw) return mergeWithCatalog(JSON.parse(raw) as DashboardLayout);
  } catch (_e) { /* ignore */ }
  return { widgets: buildPresetLayout(presetKey) };
}

export function useDashboardLayout() {
  const { profile, roles, isAdmin } = useAuth();
  const userId = profile?.id || 'anonymous';
  const presetKey = presetKeyForRoles(roles ?? [], isAdmin);

  const [layout, setLayout] = useState<DashboardLayout>(() => load(userId, presetKey));

  useEffect(() => {
    setLayout(load(userId, presetKey));
  }, [userId, presetKey]);

  const persist = useCallback((next: DashboardLayout) => {
    try {
      localStorage.setItem(getStorageKey(userId, presetKey), JSON.stringify(next));
    } catch (_e) { /* ignore */ }
  }, [userId, presetKey]);

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
    try {
      localStorage.removeItem(getStorageKey(userId, presetKey));
    } catch (_e) { /* ignore */ }
  }, [userId, presetKey]);

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
    applyPreset,
    toggleWidget,
    reorderWidgets,
    resetLayout,
    isWidgetVisible,
    getWidgetOrder,
    saveLayout,
  };
}
