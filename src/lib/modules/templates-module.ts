import { logger } from '@/lib/logger';
import { defineModule } from '@/lib/module-def';
import type { SkillSeed } from '@/lib/module-bootstrap';
import { z } from 'zod';

const templatesInputSchema = z.object({
  action: z.enum(['export', 'import', 'install']),
  templateId: z.string().optional(),
  meta: z.record(z.unknown()).optional(),
});

const templatesOutputSchema = z.object({
  success: z.boolean(),
  error: z.string().optional(),
  templateId: z.string().optional(),
});

type TemplatesInput = z.infer<typeof templatesInputSchema>;
type TemplatesOutput = z.infer<typeof templatesOutputSchema>;

const TEMPLATE_SKILLS: SkillSeed[] = [
  {
    name: 'list_templates',
    description:
      'List the starter-template catalog (bundled template JSON) plus which template (if any) is currently installed on this site. Use when: a user asks "what templates are available?", "what site am I running?", or before installing/switching a template. NOT for: actually installing a template (use install_template — a staged skill) or exporting the current site (use export_site_template).',
    category: 'system',
    handler: 'module:templates',
    scope: 'internal',
    tool_definition: {
      type: 'function',
      function: {
        name: 'list_templates',
        description: 'List available templates and the currently installed one.',
        parameters: {
          type: 'object',
          properties: {
            action: { type: 'string', enum: ['list'] },
          },
          required: ['action'],
        },
      },
    },
    instructions:
      'Returns { catalog: [...], installed: {...} | null }. Catalog rows have id/name/tagline/category plus content counts (pages/blog_posts/kb_categories/products) and required_modules. installed has template_id, template_name, installed_at. To actually install, use install_template (staged).',
  },
  {
    name: 'manage_site_template',
    description:
      "Author the instance's own SITE templates: get, create, update or archive the reusable website bodies (pages, blocks, branding, header/footer/SEO) that install_template turns into a live site. IMPORTANT: load this skill's full instructions (read_skill / skill_read) BEFORE composing — they carry the page recipes, the StarterTemplate body shape, the composition rules and what belongs in settings rather than in a page. Call describe_blocks for exact field names; a guessed key is silently dropped and the section renders empty. Every create/update returns `validation` — a non-empty errors list means the write was REFUSED. Use when: the business wants its own starter site, a new vertical needs a template, or you are asked to design a website. NOT for: installing one (install_template), editing the live site's pages (manage_page_blocks), or exporting the current site (export_site_template).",
    category: 'system',
    handler: 'rpc:manage_site_template',
    scope: 'internal',
    trust_level: 'notify',
    tool_definition: {
      type: 'function',
      function: {
        name: 'manage_site_template',
        description: 'Get, create, update or archive a reusable site template stored on this instance.',
        parameters: {
          type: 'object',
          properties: {
            action: { type: 'string', enum: ['list', 'get', 'create', 'update', 'archive'] },
            template: { type: 'string', description: "REQUIRED for get/update/archive — the template's exact name or its UUID. A unique name prefix also resolves; an ambiguous one errors with the candidates listed." },
            name: { type: 'string', description: 'REQUIRED for create. On update, renames the template.' },
            description: { type: 'string', description: 'One line on who this template is for — what an admin reads in the picker.' },
            category: { type: 'string', description: "Grouping in the picker, e.g. 'agency', 'saas', 'ecommerce'." },
            icon: { type: 'string', description: 'Lucide icon name (PascalCase) for the picker.' },
            tagline: { type: 'string', description: 'Short pitch shown under the name.' },
            template_json: { type: 'object', description: 'REQUIRED for create — the StarterTemplate body: { pages[], blogPosts[], branding, chatSettings, headerSettings, footerSettings, seoSettings, siteSettings{homepageSlug}, requiredModules[] }. On update, omit to leave unchanged.' },
            is_active: { type: 'boolean' },
          },
          required: ['action'],
          'x-action-required': { create: ['name', 'template_json'], get: ['template'], update: ['template'], archive: ['template'] },
        },
      },
    },
    instructions: `THE SITE COMPOSITION GUIDE — FlowWink owns the framework; the INSTANCE owns the content.

STEP 0, GATHER CONTEXT FIRST (never compose from a blank page):
1. \`manage_site_template action=list\` and \`list_templates\` — the existing templates ARE the house style; mirror their page set, section rhythm and voice.
2. \`describe_blocks\` — the block vocabulary with exact field names. Never guess a field name from an example; a wrong key is silently dropped and the section renders empty.
3. \`search_kb\` / \`search_wiki\` for the instance's positioning, tone and product language.
The platform supplies structure; the instance's own material supplies the words. Do not invent claims, customer names, metrics or logos — placeholder copy that reads as placeholder beats fabricated proof.

THE BODY: \`template_json\` is a StarterTemplate — \`{ pages[], blogPosts[], branding, chatSettings, headerSettings, footerSettings, seoSettings, siteSettings{homepageSlug}, requiredModules[] }\`. Each page is \`{ title, slug, isHomePage?, blocks[], meta{}, menu_order?, showInMenu? }\`. Each block is \`{ type, data{} }\` where \`data\` matches that block type exactly.

RICH TEXT: fields typed \`tiptap\` MUST be JSON objects — \`{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"…"}]}]}\` — never strings. A stringified doc renders as nothing and looks correct in the payload; \`create\` refuses it and names the field.

PAGE RECIPES (a starting rhythm, not a rule):
- **home**: hero → features or bento-grid → two-column story → social proof (testimonials / logos / stats) → CTA.
- **services/products**: hero → pricing or comparison → accordion (objections) → CTA.
- **about**: two-column story → timeline → team → CTA.
- **contact**: contact or form → map, and nothing else competing for the eye.
- **support/help**: ai-faq or accordion → quick-links → chat-launcher.

COMPOSITION:
- Use the blocks' full range. A page written with only title+content looks like the poor cousin of what the renderer can do. \`two-column\` is the most underused: \`eyebrow\` + \`eyebrowColor\`, \`titleSize\` (default | large | display), \`accentText\` with \`accentPosition\`, \`imageAspect\` / \`imageFit\` / \`imageRounded\`, \`secondImageSrc\`, \`stickyColumn\`, \`ctaText\`/\`ctaUrl\` with \`note\`.
- Alternate eyebrows across sections instead of repeating H2-only headers. At most one \`accentText\` per page — it is seasoning, not sauce.
- Every page needs one clear next action. Two CTAs competing on the same screen is none.
- \`features\` requires an \`icon\` on every item (PascalCase Lucide names).
- Full-bleed blocks (hero, parallax-section, marquee, featured-carousel) already span the viewport — do not wrap them in a container-style section.

WHAT BELONGS WHERE: branding, header, footer, SEO and cookie settings are template-level, not page blocks — a logo pasted into a hero is not a header. \`requiredModules\` lists what the template's pages actually need (a booking block needs the booking module); it is a declaration, not a switch.

MECHANICS: \`create\` is idempotent on name — an existing name returns \`already_existed: true\`; use \`action=update\` to change a body. Every create/update returns \`validation\` — a non-empty \`errors\` list means the write was refused; \`warnings\` are advice worth reading. \`archive\` deactivates; templates are not deleted, because an installed site's provenance points back at them.`,
  },

  {
    name: 'install_template',
    description:
      'Install a starter template — either from the bundled catalog OR one authored on this instance (site_templates): seeds pages, blog posts, KB categories/articles, products (and consultants/booking data when the template ships them), then records an installed_template manifest so the next install can cleanly uninstall it. template_id accepts a catalog id (from list_templates) or a stored template\'s name/UUID (from manage_site_template action=list) — that is what closes the authoring loop: compose with manage_site_template, install with this. Existing live content is preserved — colliding slugs/names are skipped and reported. Use when: asked to "install/apply/switch to the X template", put an authored template live, set up a demo site, or seed starter content. NOT for: listing what is available (list_templates for the catalog, manage_site_template action=list for authored ones), exporting the current site (use export_site_template), or creating a single page/post (use the pages/blog skills).',
    category: 'system',
    handler: 'module:templates',
    scope: 'internal',
    trust_level: 'approve',
    requires_staging: true,
    tool_definition: {
      type: 'function',
      function: {
        name: 'install_template',
        description: 'Install a catalog template: seed pages/posts/KB/products and record the install manifest.',
        parameters: {
          type: 'object',
          properties: {
            template_id: {
              type: 'string',
              description: "Catalog template id (from list_templates), e.g. 'momentum', 'launchpad', 'blank' — OR the name/UUID of a template authored on this instance (manage_site_template action=list). An unknown value answers with both lists.",
            },
            publish: {
              type: 'boolean',
              description: 'Create content as published (default true). Pass false to seed everything as drafts.',
            },
            apply_settings: {
              type: 'boolean',
              description: 'Also merge template branding/chat/header/footer/SEO/cookie settings, homepage slug and required modules into site_settings (default false — content only).',
            },
            include_pages: { type: 'boolean', description: 'Seed pages (default true).' },
            include_blog_posts: { type: 'boolean', description: 'Seed blog posts (default true when the template has any).' },
            include_kb: { type: 'boolean', description: 'Seed KB categories + articles (default true when the template has any).' },
            include_products: { type: 'boolean', description: 'Seed products + stock (default true when the template has any).' },
          },
          required: ['template_id'],
        },
      },
    },
    instructions:
      'DOUBLE-GATED SKILL (requires_staging=true AND trust_level=approve): the first call does NOT install anything — it returns { staged: true, operation_id } with a preview. Handshake: 1) call install_template with your arguments, 2) call approve_pending_operation with p_id=<operation_id> (admin approval), 3) re-invoke install_template with the SAME arguments plus BOTH _approved_operation_id=<operation_id> AND _approved=true (passing only _approved_operation_id consumes the staged operation but stops at the trust gate with status=pending_approval). On execute it first uninstalls the previously installed template via its manifest (only resources that template created), then seeds content. Returns { created, skipped, manifest, uninstalled_previous, notes }. Colliding live slugs/names are skipped, never overwritten. Image URLs are used as-is (no media-library download). Site settings are untouched unless apply_settings=true.',
  },
  {
    name: 'export_site_template',
    description:
      'Export the current site as a reusable StarterTemplate JSON: serializes published pages (with blocks + meta), published blog posts, branding/chat/header/footer/SEO/cookie settings, homepage slug and enabled modules, and validates the result. Read-only — nothing is written. Use when: asked to "export this site as a template", back up the site structure, clone the site to another instance, or inspect what a template of this site would contain. NOT for: installing templates (use install_template), listing the catalog (use list_templates), or exporting media files (images are referenced by URL only).',
    category: 'system',
    handler: 'module:templates',
    scope: 'internal',
    tool_definition: {
      type: 'function',
      function: {
        name: 'export_site_template',
        description: 'Serialize the current site (pages, posts, settings) into StarterTemplate JSON.',
        parameters: {
          type: 'object',
          properties: {
            id: { type: 'string', description: "Template id for the export (lowercase-hyphens, default 'site-export')." },
            name: { type: 'string', description: "Template display name (default 'Site Export')." },
            description: { type: 'string', description: 'Template description.' },
            category: {
              type: 'string',
              enum: ['startup', 'enterprise', 'compliance', 'platform', 'helpcenter'],
              description: "Gallery category (default 'enterprise').",
            },
            icon: { type: 'string', description: "Lucide icon name (default 'Sparkles')." },
            tagline: { type: 'string', description: 'Short gallery tagline.' },
          },
        },
      },
    },
    instructions:
      'Returns { template, validation: { valid, errors, warnings }, stats: { pages, blocks, blog_posts } }. The template object matches the StarterTemplate shape consumed by install_template / the admin Template Import tab, so the output can be re-imported on any FlowWink instance. Only PUBLISHED pages and blog posts are included; KB articles and products are not part of the export (same as the admin export page). Image URLs are referenced, not embedded.',
  },
];

export const templatesModule = defineModule<TemplatesInput, TemplatesOutput>({
  id: 'templates',
  name: 'Templates',
  version: '1.0.0',
  processes: [],
  maturity: 'L3',
  description: 'Template gallery, export current site as reusable template, and import templates from file',
  capabilities: ['data:read', 'data:write'],
  tier: 'core',
  inputSchema: templatesInputSchema,
  outputSchema: templatesOutputSchema,

  skills: ['list_templates', 'install_template', 'export_site_template'],
  skillSeeds: TEMPLATE_SKILLS,

  async publish(input: TemplatesInput): Promise<TemplatesOutput> {
    logger.log('[TemplatesModule] Action:', input.action);
    return { success: true, templateId: input.templateId };
  },
});
