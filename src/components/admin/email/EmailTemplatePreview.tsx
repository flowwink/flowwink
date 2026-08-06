/**
 * Renders a template the way the recipient will receive it: tokens filled with
 * sample values, wrapped in the same branded shell `email-send` applies.
 *
 * The frame is drawn in an <iframe srcDoc>, not a <div>. Mail HTML inherits
 * nothing from the admin app's stylesheet in a real inbox, and a preview that
 * borrows Tailwind's reset would flatter markup that breaks in Outlook.
 */
import { useMemo } from 'react';
import { useBrandingSettings, useGeneralSettings } from '@/hooks/useSiteSettings';
import {
  buildShellFromSettings,
  renderTokens,
  wrapInShell,
} from '@/lib/email-preview';

interface Props {
  subject: string;
  html: string;
  values: Record<string, string>;
  /** Height of the preview frame; the sheet and the dialog want different ones. */
  className?: string;
}

export function EmailTemplatePreview({ subject, html, values, className }: Props) {
  const { data: branding } = useBrandingSettings();
  const { data: general } = useGeneralSettings();

  const shell = useMemo(
    () => buildShellFromSettings(branding, general),
    [branding, general],
  );

  const renderedSubject = renderTokens(subject, values);
  const doc = useMemo(
    () => wrapInShell(renderTokens(html, values), shell),
    [html, values, shell],
  );

  return (
    <div className="rounded-md border overflow-hidden bg-muted/30">
      <div className="border-b bg-background px-3 py-2">
        <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Subject</p>
        <p className="text-sm font-medium truncate">{renderedSubject || <span className="text-muted-foreground">(no subject)</span>}</p>
      </div>
      <iframe
        // A sandbox with no allow-scripts: template HTML is operator input and
        // an agent can write it too — it renders here, it does not run here.
        sandbox=""
        srcDoc={doc}
        title="Email preview"
        className={className ?? 'w-full h-[420px] bg-white'}
      />
    </div>
  );
}

/**
 * The brand's logo is the one part of the shell an operator cannot fix from
 * this screen, so say it plainly where they will see the consequence.
 */
export function EmailLogoNotice() {
  const { data: branding } = useBrandingSettings();
  const logo = branding?.logo?.trim();
  const hasEmailLogo = !!branding?.logoEmail?.trim();
  const svgOnly = !hasEmailLogo && !!logo && logo.split('?')[0].toLowerCase().endsWith('.svg');
  if (!svgOnly) return null;

  return (
    <p className="text-xs text-muted-foreground border rounded-md p-2 bg-muted/40">
      Your brand logo is an SVG, which Gmail and Outlook block in email. The
      shell falls back to the organisation name as text. Upload a PNG as
      <span className="font-medium"> Email logo</span> under Branding to show
      the mark instead.
    </p>
  );
}
