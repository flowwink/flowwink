-- Dashboard layouts, per user and per role preset. Replaces localStorage-only
-- persistence so a layout follows the user across browsers and devices.
CREATE TABLE IF NOT EXISTS public.user_dashboard_layouts (
  user_id UUID NOT NULL,
  preset_key TEXT NOT NULL,
  widgets JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, preset_key)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_dashboard_layouts TO authenticated;
GRANT ALL ON public.user_dashboard_layouts TO service_role;

ALTER TABLE public.user_dashboard_layouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage their own dashboard layouts" ON public.user_dashboard_layouts;
CREATE POLICY "Users manage their own dashboard layouts"
ON public.user_dashboard_layouts
FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

DROP TRIGGER IF EXISTS update_user_dashboard_layouts_updated_at ON public.user_dashboard_layouts;
CREATE TRIGGER update_user_dashboard_layouts_updated_at
BEFORE UPDATE ON public.user_dashboard_layouts
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();