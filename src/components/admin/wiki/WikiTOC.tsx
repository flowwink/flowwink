import { useMemo } from 'react';

interface Props {
  content: string;
}

interface Heading {
  id: string;
  text: string;
  level: number;
}

function slugify(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-');
}

/** Extract h2/h3 headings from markdown for an on-page outline. */
export function extractHeadings(md: string): Heading[] {
  const out: Heading[] = [];
  let inFence = false;
  for (const line of (md || '').split('\n')) {
    if (line.trim().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const m = /^(#{2,3})\s+(.+?)\s*$/.exec(line);
    if (m) out.push({ level: m[1].length, text: m[2], id: slugify(m[2]) });
  }
  return out;
}

export function WikiTOC({ content }: Props) {
  const headings = useMemo(() => extractHeadings(content), [content]);
  if (headings.length < 2) return null;

  return (
    <nav aria-label="On this page" className="sticky top-6 space-y-1">
      <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
        On this page
      </p>
      <ul className="space-y-0.5 border-l">
        {headings.map((h) => (
          <li key={h.id}>
            <a
              href={`#${h.id}`}
              className={`block truncate border-l-2 border-transparent py-0.5 text-xs text-muted-foreground hover:border-primary hover:text-foreground ${
                h.level === 3 ? 'pl-5' : 'pl-3'
              }`}
            >
              {h.text}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
