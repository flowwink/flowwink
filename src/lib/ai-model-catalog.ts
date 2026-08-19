import {
  defaultIntegrationsSettings,
  type IntegrationsSettings,
} from '@/hooks/useIntegrations';

/**
 * The curated model catalog — one half of the AI model split.
 *
 *   Integrations   = AVAILABILITY. Credentials plus the gross list of model
 *                    names this instance is allowed to use (`config.models`).
 *   System Settings = POLICY. Which of those models is USED for which tier
 *                    (site_settings key='system_ai', the model map).
 *
 * The catalog never says what runs — only what is approved. Keeping it on the
 * integrations row means "what this key can reach" travels with the key.
 *
 * Free text stays legal (Law 4 — fail forward, don't gate): a name typed in the
 * model map that the catalog has not seen is added to the catalog in the same
 * gesture rather than rejected, so a model released today works today.
 */

export type CatalogProvider = 'openai' | 'gemini' | 'anthropic';

export const CATALOG_PROVIDERS: readonly CatalogProvider[] = ['openai', 'gemini', 'anthropic'];

export function isCatalogProvider(value: string): value is CatalogProvider {
  return (CATALOG_PROVIDERS as readonly string[]).includes(value);
}

/**
 * Fallback catalog used only when the integrations row has never carried a list
 * for that provider. An admin who curates the list owns it from then on —
 * including removals, which is why a stored (even empty) list wins outright.
 */
export const DEFAULT_MODEL_CATALOG: Record<CatalogProvider, string[]> = {
  openai: ['gpt-5.6-luna', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano'],
  gemini: ['gemini-2.5-pro', 'gemini-2.5-flash'],
  anthropic: ['claude-sonnet-4-20250514'],
};

/** Which model-map fields each provider owns in `site_settings.system_ai`. */
export const SYSTEM_AI_MODEL_FIELDS: Record<
  CatalogProvider,
  { fast: 'openaiModel' | 'geminiModel' | 'anthropicModel'; reasoning: 'openaiReasoningModel' | 'geminiReasoningModel' | 'anthropicReasoningModel' }
> = {
  openai: { fast: 'openaiModel', reasoning: 'openaiReasoningModel' },
  gemini: { fast: 'geminiModel', reasoning: 'geminiReasoningModel' },
  anthropic: { fast: 'anthropicModel', reasoning: 'anthropicReasoningModel' },
};

/** Model ids are opaque provider strings — trim only, never rewrite the case. */
export function normalizeModelName(name: string): string {
  return (name ?? '').trim();
}

function dedupe(names: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of names) {
    const name = normalizeModelName(raw);
    if (!name || seen.has(name)) continue;
    seen.add(name);
    out.push(name);
  }
  return out;
}

/**
 * The approved model names for a provider. A list stored on the integrations
 * row is authoritative (so a removal sticks); otherwise the defaults apply.
 */
export function getModelCatalog(
  integrations: IntegrationsSettings | undefined,
  provider: CatalogProvider,
): string[] {
  const stored = integrations?.[provider]?.config?.models;
  if (Array.isArray(stored)) return dedupe(stored);
  return [...DEFAULT_MODEL_CATALOG[provider]];
}

/**
 * Merge patch that adds names to a provider's catalog, or null when there is
 * nothing new. Every other key in `config` is carried over untouched — the same
 * merge discipline the ui_text pack uses; a catalog write must never be a
 * silent overwrite of credentials or budget fields.
 */
export function addModelsToCatalogPatch(
  integrations: IntegrationsSettings | undefined,
  provider: CatalogProvider,
  models: string[],
): Partial<IntegrationsSettings> | null {
  const current = getModelCatalog(integrations, provider);
  const additions = dedupe(models).filter((name) => !current.includes(name));
  if (additions.length === 0) return null;
  return setModelCatalogPatch(integrations, provider, [...current, ...additions]);
}

/** Merge patch that replaces a provider's catalog with an explicit list. */
export function setModelCatalogPatch(
  integrations: IntegrationsSettings | undefined,
  provider: CatalogProvider,
  models: string[],
): Partial<IntegrationsSettings> {
  const existing = integrations?.[provider] ?? defaultIntegrationsSettings[provider];
  return {
    [provider]: {
      ...existing,
      config: { ...(existing?.config ?? {}), models: dedupe(models) },
    },
  } as Partial<IntegrationsSettings>;
}
