/**
 * AI transports + embedding-provider resolution shared by chat-completion and
 * any other surface that talks to OpenAI-compatible providers, Gemini, a local
 * OpenAI-compatible LLM, or an n8n webhook.
 *
 * CHAT-MODEL RESOLUTION NO LONGER LIVES HERE. Since the AI-model-map refactor,
 * surfaces declare a TIER and `resolveAiConfig(supabase, tier)` in ./ai-config.ts
 * reads the platform map (site_settings key='system_ai') to pick provider+model;
 * Integrations only carry credentials. The old per-surface resolvers
 * (`tryResolveProvider` / `resolveProviderWithFallback`) read model fields off
 * the chat settings row and were removed with their last consumer — do not
 * reintroduce them. What remains here is transport and shape:
 * ProviderConfig, the n8n passthrough, upstream error mapping, the
 * reasoning-model predicate, and embedding-provider resolution (embeddings are
 * not part of the tier map).
 */

export interface ChatSettingsLike {
  aiProvider?: 'openai' | 'gemini' | 'local' | 'n8n';
  openaiApiKey?: string;
  openaiModel?: string;
  openaiBaseUrl?: string;
  geminiApiKey?: string;
  geminiModel?: string;
  localEndpoint?: string;
  localModel?: string;
  localApiKey?: string;
  localSupportsToolCalling?: boolean;
  n8nWebhookUrl?: string;
  n8nWebhookType?: 'chat' | 'generic';
}

export interface ChatMessageLike {
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: any;
  tool_call_id?: string;
  tool_calls?: any[];
}

export interface ProviderConfig {
  apiKey: string;
  apiUrl: string;
  model: string;
  supportsToolCalling: boolean;
  isN8n: boolean;
  n8nConfig?: { webhookUrl: string; webhookType: string; apiKey?: string };
  resolvedProvider: string;
}

/**
 * gpt-5-class / o-series models are reasoning models: on /v1/chat/completions
 * they reject function tools unless `reasoning_effort` is 'none' (OpenAI 400s
 * with "use /v1/responses or set reasoning_effort to 'none'"), and reject
 * `max_tokens` in favour of `max_completion_tokens`. Callers that attach tools
 * must gate the param on this check — sending reasoning_effort to a non-
 * reasoning model (gpt-4.1-*) is its own 400.
 */
export function isOpenAiReasoningModel(model: string): boolean {
  return /^(gpt-5|o[0-9])/.test(model);
}

// ---------------------------------------------------------------------------
// Embeddings
// ---------------------------------------------------------------------------

export interface EmbeddingResult {
  embedding: number[];
  model: string;
  provider: string;
}

/**
 * Resolve provider for embeddings. Falls back OpenAI → Gemini → Local.
 * (n8n is skipped — it's a chat webhook, not an embedding endpoint.)
 *
 * Returns a config tailored for the `/embeddings` endpoint, not chat.
 */
export interface EmbeddingProviderConfig {
  provider: 'openai' | 'gemini' | 'local';
  apiKey: string;
  apiUrl: string;
  model: string;
  dimensions: number;
}

export function resolveEmbeddingProvider(
  settings: ChatSettingsLike | undefined,
  integrations: any,
  preferred?: 'openai' | 'gemini' | 'local',
): EmbeddingProviderConfig {
  const order: Array<'openai' | 'gemini' | 'local'> = preferred
    ? [preferred, ...(['openai', 'gemini', 'local'] as const).filter(p => p !== preferred)]
    : ['openai', 'gemini', 'local'];

  for (const p of order) {
    if (p === 'openai') {
      const apiKey = settings?.openaiApiKey || Deno.env.get('OPENAI_API_KEY');
      if (!apiKey) continue;
      const baseUrl = settings?.openaiBaseUrl || 'https://api.openai.com/v1';
      return {
        provider: 'openai',
        apiKey,
        apiUrl: `${baseUrl}/embeddings`,
        model: 'text-embedding-3-small',
        dimensions: 1536,
      };
    }
    if (p === 'gemini') {
      const apiKey = settings?.geminiApiKey || Deno.env.get('GEMINI_API_KEY');
      if (!apiKey) continue;
      // Use OpenAI-compatible endpoint for Gemini embeddings
      return {
        provider: 'gemini',
        apiKey,
        apiUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/embeddings',
        model: 'text-embedding-004',
        dimensions: 1536, // we truncate via `dimensions` param
      };
    }
    if (p === 'local') {
      const localConfig = integrations?.local_llm?.config || {};
      const endpoint = localConfig?.endpoint || settings?.localEndpoint;
      if (!endpoint || endpoint.includes('placeholder')) continue;
      const apiKey = Deno.env.get('LOCAL_LLM_API_KEY') || localConfig?.apiKey || settings?.localApiKey || '';
      const base = endpoint.replace(/\/+$/, '');
      const path = base.endsWith('/v1') ? '/embeddings' : '/v1/embeddings';
      return {
        provider: 'local',
        apiKey,
        apiUrl: `${base}${path}`,
        model: localConfig?.embeddingModel || 'text-embedding-3-small',
        dimensions: 1536,
      };
    }
  }

  throw new Error('No embedding provider available. Configure OpenAI, Gemini or Local LLM API keys in Settings → System AI.');
}

/** Embed a single piece of text. Returns the vector + model used. */
export async function embedText(
  text: string,
  cfg: EmbeddingProviderConfig,
): Promise<EmbeddingResult> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (cfg.apiKey) headers['Authorization'] = `Bearer ${cfg.apiKey}`;

  const body: Record<string, any> = {
    model: cfg.model,
    input: text.slice(0, 8000), // safety cap
  };
  // OpenAI v3 supports `dimensions` truncation; harmless if ignored.
  if (cfg.provider === 'openai' || cfg.provider === 'gemini') {
    body.dimensions = cfg.dimensions;
  }

  const resp = await fetch(cfg.apiUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    const t = await resp.text();
    throw new Error(`Embedding provider ${cfg.provider} error ${resp.status}: ${t}`);
  }

  const data = await resp.json();
  const vec = data?.data?.[0]?.embedding;
  if (!Array.isArray(vec)) throw new Error(`Embedding provider ${cfg.provider} returned no vector`);
  return { embedding: vec, model: cfg.model, provider: cfg.provider };
}


/**
 * N8N webhook passthrough. Returns an SSE Response that mimics the
 * OpenAI streaming-completion format so client code is provider-agnostic.
 */
export async function handleN8nWebhook(
  n8nConfig: NonNullable<ProviderConfig['n8nConfig']>,
  fullMessages: ChatMessageLike[],
  conversationId: string | undefined,
  sessionId: string | undefined,
  systemPrompt: string | undefined,
  corsHeaders: Record<string, string>,
): Promise<Response> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (n8nConfig.apiKey) {
    headers['Authorization'] = n8nConfig.apiKey.startsWith('Bearer ')
      ? n8nConfig.apiKey
      : `Bearer ${n8nConfig.apiKey}`;
  }

  const lastUserMessage = fullMessages.filter(m => m.role === 'user').pop();
  const payload = n8nConfig.webhookType === 'chat'
    ? { chatInput: lastUserMessage?.content || '', sessionId: sessionId || conversationId, systemPrompt }
    : { messages: fullMessages, model: 'gpt-4', conversationId, sessionId };

  const resp = await fetch(n8nConfig.webhookUrl, {
    method: 'POST', headers, body: JSON.stringify(payload),
  });

  if (!resp.ok) {
    const errorText = await resp.text();
    console.error('[ai-providers] N8N webhook error:', resp.status, errorText);
    throw new Error('N8N webhook failed');
  }

  const data = await resp.json();
  let responseContent = 'I could not process your request.';
  if (Array.isArray(data) && data.length > 0) {
    responseContent = data[0].output || data[0].message || data[0].response || responseContent;
  } else if (typeof data === 'object' && data !== null) {
    responseContent = data.output || data.message || data.response || responseContent;
  }

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    start(controller) {
      const sseData = JSON.stringify({ choices: [{ delta: { content: responseContent }, finish_reason: 'stop' }] });
      controller.enqueue(encoder.encode(`data: ${sseData}\n\n`));
      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      controller.close();
    },
  });

  return new Response(stream, { headers: { ...corsHeaders, 'Content-Type': 'text/event-stream' } });
}

/** Map upstream AI provider errors to clean client-facing JSON responses. */
export async function handleAiError(
  response: Response,
  corsHeaders: Record<string, string>,
): Promise<Response> {
  if (response.status === 429) {
    return new Response(JSON.stringify({ error: 'Too many requests. Please wait and try again.' }), {
      status: 429, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  if (response.status === 402) {
    return new Response(JSON.stringify({ error: 'Credits exhausted. Contact administrator.' }), {
      status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
  const errorText = await response.text();
  console.error('[ai-providers] AI provider error:', response.status, errorText);
  return new Response(JSON.stringify({ error: 'AI service error.' }), {
    status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
