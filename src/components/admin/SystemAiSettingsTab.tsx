import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { Info, Sparkles, ExternalLink, Server, Eye, Zap, Brain, AlertTriangle } from 'lucide-react';
import { SystemAiSettings, SystemAiProvider } from '@/hooks/useSiteSettings';
import { useIsOpenAIConfigured, useIsGeminiConfigured, useIsAnthropicConfigured, useIsLocalLLMConfigured } from '@/hooks/useIntegrationStatus';
import { useIntegrations } from '@/hooks/useIntegrations';
import {
  getModelCatalog,
  normalizeModelName,
  SYSTEM_AI_MODEL_FIELDS,
  type CatalogProvider,
} from '@/lib/ai-model-catalog';
import { ProvenanceLine } from '@/components/ui/provenance-line';
import { Link } from 'react-router-dom';

interface SystemAiSettingsTabProps {
  data: SystemAiSettings;
  onChange: (data: SystemAiSettings) => void;
}

const VISION_CAPABLE = new Set<SystemAiProvider>(['openai', 'gemini', 'anthropic']);
const PROVIDER_LABEL: Record<SystemAiProvider, string> = {
  openai: 'OpenAI',
  gemini: 'Google Gemini',
  anthropic: 'Anthropic (Claude)',
  local: 'Local LLM',
};

/** Hosted providers own two model-map fields; Local LLM has none (see below). */
type HostedProvider = CatalogProvider;

const MODEL_PLACEHOLDER: Record<HostedProvider, string> = {
  openai: 'e.g. gpt-4.1-mini',
  gemini: 'e.g. gemini-2.5-flash',
  anthropic: 'e.g. claude-sonnet-4-20250514',
};

/**
 * Policy field: which model this tier uses. Suggestions come from the curated
 * catalog in Integrations (availability), never from a hardcoded list here.
 *
 * Free text stays allowed — a name outside the catalog is kept and added to the
 * catalog on save, so a model that ships today is usable today. A native
 * <datalist> keeps this a plain controlled input (no combobox state to freeze).
 */
function ModelField({
  id,
  label,
  usage,
  value,
  placeholder,
  suggestions,
  onChange,
}: {
  id: string;
  label: string;
  usage: string;
  value: string;
  placeholder: string;
  suggestions: string[];
  onChange: (value: string) => void;
}) {
  const listId = `${id}-suggestions`;
  const current = normalizeModelName(value ?? '');
  const inCatalog = !current || suggestions.includes(current);
  return (
    <div className="space-y-2">
      <Label htmlFor={id}>{label}</Label>
      <Input
        id={id}
        list={listId}
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="font-mono text-sm"
        autoComplete="off"
        spellCheck={false}
      />
      <datalist id={listId}>
        {suggestions.map((model) => (
          <option key={model} value={model} />
        ))}
        {!inCatalog && <option value={current}>(not in catalog)</option>}
      </datalist>
      <p className="text-xs text-muted-foreground">{usage}</p>
      <p className="text-xs text-muted-foreground">
        Pick from the curated list or type a new name — new names are added to the catalog in
        Integrations. Model names are passed straight to the provider, so new models work as soon
        as they ship; reasoning-class models (gpt-5.x, o-series) are handled automatically.
      </p>
      {!inCatalog && (
        <ProvenanceLine>
          <span className="font-mono">{current}</span> is not in the Integrations catalog yet —
          saving adds it.
        </ProvenanceLine>
      )}
    </div>
  );
}

export function SystemAiSettingsTab({ data, onChange }: SystemAiSettingsTabProps) {
  const openaiEnabled = useIsOpenAIConfigured();
  const geminiEnabled = useIsGeminiConfigured();
  const anthropicEnabled = useIsAnthropicConfigured();
  const localEnabled = useIsLocalLLMConfigured();
  const { data: integrations } = useIntegrations();
  const hasAnyProvider = openaiEnabled || geminiEnabled || anthropicEnabled || localEnabled;

  const enabledByProvider: Record<SystemAiProvider, boolean> = {
    openai: openaiEnabled,
    gemini: geminiEnabled,
    anthropic: anthropicEnabled,
    local: localEnabled,
  };

  // Default models used by edge functions when no explicit override is set.
  // Keep in sync with supabase/functions/_shared/ai-config.ts.
  const DEFAULT_FALLBACK_MODEL: Record<SystemAiProvider, { fast: string; reasoning: string; multimodal: string }> = {
    openai: { fast: 'gpt-4.1-mini', reasoning: 'gpt-5.6-luna', multimodal: 'gpt-4.1-mini' },
    gemini: { fast: 'gemini-2.5-flash', reasoning: 'gemini-2.5-pro', multimodal: 'gemini-2.5-flash' },
    anthropic: { fast: 'claude-3-5-haiku', reasoning: 'claude-3-5-sonnet', multimodal: 'claude-3-5-sonnet' },
    local: { fast: '', reasoning: '', multimodal: '' },
  };

  // Mirror of resolveAiConfig() server-side logic for UI display.
  // For 'fast'/'reasoning': use selected provider if configured, otherwise auto-fall-back to env.
  // For 'multimodal': only vision-capable providers count; local LLM forces fallback.
  const resolveTier = (tier: 'fast' | 'reasoning' | 'multimodal'): {
    provider: SystemAiProvider | null;
    fallback: boolean;
    fallbackModel?: string;
  } => {
    const primary = data.provider as SystemAiProvider;

    const withFallbackModel = (provider: SystemAiProvider) => ({
      provider,
      fallback: !!primary,
      fallbackModel: DEFAULT_FALLBACK_MODEL[provider]?.[tier],
    });

    if (tier === 'multimodal') {
      if (primary && VISION_CAPABLE.has(primary) && enabledByProvider[primary]) {
        return { provider: primary, fallback: false };
      }
      if (geminiEnabled) return withFallbackModel('gemini');
      if (openaiEnabled) return withFallbackModel('openai');
      if (anthropicEnabled) return withFallbackModel('anthropic');
      return { provider: null, fallback: false };
    }

    if (primary && enabledByProvider[primary]) {
      return { provider: primary, fallback: false };
    }
    if (openaiEnabled) return withFallbackModel('openai');
    if (anthropicEnabled) return withFallbackModel('anthropic');
    if (geminiEnabled) return withFallbackModel('gemini');
    return { provider: null, fallback: false };
  };

  const fastTier = resolveTier('fast');
  const reasoningTier = resolveTier('reasoning');
  const multimodalTier = resolveTier('multimodal');

  // Local LLM configures endpoint + model together in Integrations (they are one
  // credential); every other provider owns its two model-map fields here.
  const hostedProvider: HostedProvider | null =
    data.provider === 'local' ? null : (data.provider as CatalogProvider);
  const catalog = hostedProvider ? getModelCatalog(integrations, hostedProvider) : [];

  const updateField = <K extends keyof SystemAiSettings>(key: K, value: SystemAiSettings[K]) => {
    onChange({ ...data, [key]: value });
  };

  return (
    <div className="space-y-6">
      <Alert>
        <Info className="h-4 w-4" />
        <AlertTitle>What is System AI?</AlertTitle>
        <AlertDescription>
          This is the platform's AI model map — the one place a model is chosen. It powers internal
          tools (text generation, company enrichment, lead qualification, content migration),
          FlowPilot, and the visitor-facing AI Chat, which reads the fast tier from here.
          Integrations only holds the credentials.
        </AlertDescription>
      </Alert>

      {!hasAnyProvider && (
        <Alert variant="destructive">
          <AlertTitle>No AI Provider Configured</AlertTitle>
          <AlertDescription>
            You need to enable OpenAI, Gemini, or Anthropic in{' '}
            <Link to="/admin/integrations#ai" className="underline font-medium hover:text-destructive-foreground inline-flex items-center gap-1">
              Integrations <ExternalLink className="h-3 w-3" />
            </Link>{' '}
            and add the API key, or configure a Local LLM endpoint, before System AI features will work.
          </AlertDescription>
        </Alert>
      )}

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="font-serif flex items-center gap-2">
              <Sparkles className="h-5 w-5" />
              AI Provider
            </CardTitle>
            <CardDescription>Choose which AI provider powers internal tools</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label>Provider</Label>
              <Select
                value={data.provider}
                onValueChange={(value: SystemAiProvider) => updateField('provider', value)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="openai" disabled={!openaiEnabled}>
                    <div className="flex items-center gap-2">
                      OpenAI
                      {openaiEnabled ? (
                        <Badge variant="outline" className="text-xs">Enabled</Badge>
                      ) : (
                        <Badge variant="secondary" className="text-xs">Not configured</Badge>
                      )}
                    </div>
                  </SelectItem>
                  <SelectItem value="gemini" disabled={!geminiEnabled}>
                    <div className="flex items-center gap-2">
                      Google Gemini
                      {geminiEnabled ? (
                        <Badge variant="outline" className="text-xs">Enabled</Badge>
                      ) : (
                        <Badge variant="secondary" className="text-xs">Not configured</Badge>
                      )}
                    </div>
                  </SelectItem>
                  <SelectItem value="anthropic" disabled={!anthropicEnabled}>
                    <div className="flex items-center gap-2">
                      Anthropic (Claude)
                      {anthropicEnabled ? (
                        <Badge variant="outline" className="text-xs">Enabled</Badge>
                      ) : (
                        <Badge variant="secondary" className="text-xs">Not configured</Badge>
                      )}
                    </div>
                  </SelectItem>
                  <SelectItem value="local" disabled={!localEnabled}>
                    <div className="flex items-center gap-2">
                      Local LLM
                      {localEnabled ? (
                        <Badge variant="outline" className="text-xs">Enabled</Badge>
                      ) : (
                        <Badge variant="secondary" className="text-xs">Not configured</Badge>
                      )}
                    </div>
                  </SelectItem>
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="font-serif">Content Preferences</CardTitle>
            <CardDescription>Default settings for AI-generated content</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label>Default Tone</Label>
              <Select
                value={data.defaultTone}
                onValueChange={(value: SystemAiSettings['defaultTone']) => updateField('defaultTone', value)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="professional">Professional</SelectItem>
                  <SelectItem value="friendly">Friendly</SelectItem>
                  <SelectItem value="formal">Formal</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                Used when generating or improving text content
              </p>
            </div>

            <div className="space-y-2">
              <Label>Default Language</Label>
              <Select
                value={data.defaultLanguage}
                onValueChange={(value) => updateField('defaultLanguage', value)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="sv">Swedish</SelectItem>
                  <SelectItem value="en">English</SelectItem>
                  <SelectItem value="no">Norwegian</SelectItem>
                  <SelectItem value="da">Danish</SelectItem>
                  <SelectItem value="fi">Finnish</SelectItem>
                  <SelectItem value="de">German</SelectItem>
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">
                Primary language for content generation
              </p>
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="font-serif flex items-center gap-2">
            <Sparkles className="h-5 w-5" />
            Model Configuration
          </CardTitle>
          <CardDescription>
            Two tiers per provider: a fast model for real-time chat and tool execution — used by
            FlowPilot and by the visitor-facing chat — and a reasoning model for deep analysis,
            research, and planning.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {hostedProvider && (
            <div className="space-y-4">
              <div className="grid gap-6 md:grid-cols-2">
                <ModelField
                  id={`${hostedProvider}-fast-model`}
                  label="Chat & Interaction Model"
                  usage="Used for real-time chat, tool calls, and quick tasks — including the visitor-facing AI chat."
                  value={data[SYSTEM_AI_MODEL_FIELDS[hostedProvider].fast]}
                  placeholder={MODEL_PLACEHOLDER[hostedProvider]}
                  suggestions={catalog}
                  onChange={(value) => updateField(SYSTEM_AI_MODEL_FIELDS[hostedProvider].fast, value)}
                />
                <ModelField
                  id={`${hostedProvider}-reasoning-model`}
                  label="Research & Reasoning Model"
                  usage="Used for objectives, planning, content research, and deep analysis."
                  value={data[SYSTEM_AI_MODEL_FIELDS[hostedProvider].reasoning]}
                  placeholder={MODEL_PLACEHOLDER[hostedProvider]}
                  suggestions={catalog}
                  onChange={(value) => updateField(SYSTEM_AI_MODEL_FIELDS[hostedProvider].reasoning, value)}
                />
              </div>
              <ProvenanceLine to="/admin/integrations#ai" linkLabel="Integrations → AI">
                Suggestions come from the curated model catalog for {PROVIDER_LABEL[hostedProvider]},
                which lists what this key may use. What is used per tier is decided here.
              </ProvenanceLine>
            </div>
          )}

          {data.provider === 'local' && (
            <Alert className="bg-green-50 border-green-200 dark:bg-green-950 dark:border-green-900">
              <Server className="h-4 w-4 text-green-600" />
              <AlertTitle className="text-green-800 dark:text-green-200">Local LLM (HIPAA-compliant)</AlertTitle>
              <AlertDescription className="text-green-700 dark:text-green-300">
                System AI will use the Local LLM endpoint configured in{' '}
                <Link to="/admin/integrations#ai" className="underline font-medium">Integrations</Link>.
                Both fast and reasoning tiers use the same model. Your data never leaves your infrastructure.
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="font-serif flex items-center gap-2">
            <Eye className="h-5 w-5" />
            Capability Routing
          </CardTitle>
          <CardDescription>
            Which provider actually handles each tier. Multimodal (image/PDF) auto-falls back
            to a vision-capable provider if your selected one is text-only.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 sm:grid-cols-3">
            {[
              { label: 'Fast (chat, tools)', icon: Zap, tier: fastTier },
              { label: 'Reasoning (planning)', icon: Brain, tier: reasoningTier },
              { label: 'Multimodal (image/PDF)', icon: Eye, tier: multimodalTier },
            ].map(({ label, icon: Icon, tier }) => (
              <div key={label} className="rounded-lg border p-4 space-y-2">
                <div className="flex items-center gap-2 text-sm font-medium">
                  <Icon className="h-4 w-4" />
                  {label}
                </div>
                {tier.provider ? (
                  <>
                    <div className="text-base font-serif">{PROVIDER_LABEL[tier.provider]}</div>
                    {tier.fallback && (
                      <div className="space-y-1">
                        <Badge variant="secondary" className="text-xs gap-1">
                          <AlertTriangle className="h-3 w-3" />
                          Fallback (selected provider can't handle this)
                        </Badge>
                        {tier.fallbackModel && (
                          <div className="text-xs text-muted-foreground font-mono">
                            {tier.fallbackModel}
                          </div>
                        )}
                      </div>
                    )}
                  </>
                ) : (
                  <Badge variant="destructive" className="text-xs">Not available</Badge>
                )}
              </div>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="font-serif">Powered Features</CardTitle>
          <CardDescription>These features use System AI settings</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div className="rounded-lg border p-4">
              <h4 className="font-medium text-sm">Text Generation</h4>
              <p className="text-xs text-muted-foreground mt-1">
                Expand, improve, summarize, translate, and continue text in editors
              </p>
            </div>
            <div className="rounded-lg border p-4">
              <h4 className="font-medium text-sm">Company Enrichment</h4>
              <p className="text-xs text-muted-foreground mt-1">
                Auto-extract company info from websites in CRM
              </p>
            </div>
            <div className="rounded-lg border p-4">
              <h4 className="font-medium text-sm">Lead Qualification</h4>
              <p className="text-xs text-muted-foreground mt-1">
                AI-powered lead scoring and summaries
              </p>
            </div>
            <div className="rounded-lg border p-4">
              <h4 className="font-medium text-sm">Content Migration</h4>
              <p className="text-xs text-muted-foreground mt-1">
                Import pages from external websites
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
