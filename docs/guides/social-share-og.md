# Social share cards (OG/Twitter) on a self-hosted instance

When someone pastes an instance URL into WhatsApp, LinkedIn, Slack or Facebook,
the crawler fetches the page **without executing JavaScript**. A Vite SPA's
`index.html` is intentionally brandless, so unless something server-side answers
the crawler, the share shows only the bare link.

FlowWink has two layers:

| Layer | Who sees it | Source of truth |
|---|---|---|
| `SeoHead.tsx` (react-helmet) | browsers, Googlebot/bingbot (JS-capable) | `site_settings.seo` + per-page `meta_json` |
| `api/og.ts` (crawler prerender) | social crawlers | same tables, read over PostgREST with the anon key |

## Where the image is configured (no code, no redeploy)

- Sitewide: **Admin → Site Settings → SEO → OG Image** (1200×630). Upload via the
  media library or paste an absolute URL.
- Per page: the page's SEO fields (`pages.meta_json.ogImage`).
- Per blog post: `featured_image`, or the OG image field in the post editor.

Relative paths are absolutised against the request host in both layers, so a
`/storage/v1/object/public/cms-images/og.jpg` value works on any domain.

## Deploy path A — Vercel (supported out of the box)

`vercel.json` routes only social-crawler user-agents to `/api/og`. Requirements
on the admin's own Vercel project:

1. Environment variables must exist **at runtime**, not just at build time —
   `api/og.ts` is an Edge Function and reads
   `VITE_SUPABASE_URL` (or `SUPABASE_URL`) and
   `VITE_SUPABASE_PUBLISHABLE_KEY` (or `SUPABASE_ANON_KEY`).
   Set them for Production *and* Preview.
2. Nothing else. The anon key is enough: it only reads published
   `pages` / `blog_posts` / `site_settings` rows through RLS.

Verify:

```bash
curl -s -A "WhatsApp/2.23" https://your-domain.com/ | grep -i 'og:'
```

You should see `og:title`, `og:description`, `og:image` and a self-referencing
`og:url`. If `og:image` is missing, the SEO setting is empty — set it in admin.

## Deploy path B — Docker / nginx (needs one step)

`nginx.conf` already classifies social crawlers into `$is_social_crawler`, but
the proxy block is commented out, so crawlers currently fall through to the SPA
and get no card. Two options:

- **Static fallback (simplest):** bake a sitewide `og:image`, `og:title` and
  `og:description` into `index.html` at container start (the
  `docker/40-runtime-env.sh` entrypoint is the natural place). Gives one correct
  card for the whole site — no per-page previews.
- **Full parity:** deploy the same logic as an edge function on the instance's
  own Supabase and uncomment the `proxy_pass` in `nginx.conf`'s
  `$is_social_crawler` branch, pointing at
  `<SUPABASE_URL>/functions/v1/render-page?path=$1`.

## Caching

WhatsApp and Facebook cache the first scrape for days. After changing an image,
use Facebook's Sharing Debugger to force a re-scrape; WhatsApp piggybacks on the
same cache.
