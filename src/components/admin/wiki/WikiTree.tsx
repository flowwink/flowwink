import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { ChevronRight } from 'lucide-react';
import type { WikiPageListItem } from '@/hooks/useWiki';

interface Props {
  pages: WikiPageListItem[];
  activeSlug: string;
}

interface Node extends WikiPageListItem {
  children: Node[];
}

/** Build a parent/child tree; orphans (missing parent) are treated as roots. */
function buildTree(pages: WikiPageListItem[]): Node[] {
  const bySlug = new Map<string, Node>();
  pages.forEach((p) => bySlug.set(p.slug, { ...p, children: [] }));
  const roots: Node[] = [];
  bySlug.forEach((node) => {
    const parent = node.parent_slug ? bySlug.get(node.parent_slug) : undefined;
    if (parent && parent.slug !== node.slug) parent.children.push(node);
    else roots.push(node);
  });
  const sort = (list: Node[]) => {
    list.sort((a, b) => a.title.localeCompare(b.title));
    list.forEach((n) => sort(n.children));
  };
  sort(roots);
  return roots;
}

function ancestorsOf(pages: WikiPageListItem[], slug: string): Set<string> {
  const map = new Map(pages.map((p) => [p.slug, p]));
  const out = new Set<string>();
  let cur = map.get(slug)?.parent_slug ?? null;
  let guard = 0;
  while (cur && guard++ < 50) {
    out.add(cur);
    cur = map.get(cur)?.parent_slug ?? null;
  }
  return out;
}

function Row({
  node,
  depth,
  activeSlug,
  openSet,
  toggle,
}: {
  node: Node;
  depth: number;
  activeSlug: string;
  openSet: Set<string>;
  toggle: (slug: string) => void;
}) {
  const hasKids = node.children.length > 0;
  const open = openSet.has(node.slug);
  return (
    <li>
      <div
        className={`group flex items-center rounded hover:bg-accent ${
          node.slug === activeSlug ? 'bg-accent' : ''
        }`}
        style={{ paddingLeft: depth * 12 }}
      >
        {hasKids ? (
          <button
            type="button"
            onClick={() => toggle(node.slug)}
            aria-label={open ? 'Collapse' : 'Expand'}
            className="p-1 text-muted-foreground hover:text-foreground"
          >
            <ChevronRight
              className={`h-3 w-3 transition-transform ${open ? 'rotate-90' : ''}`}
            />
          </button>
        ) : (
          <span className="w-5" />
        )}
        <Link
          to={`/admin/wiki/${node.slug}`}
          className={`flex-1 truncate py-1.5 pr-2 text-sm ${
            node.slug === activeSlug ? 'font-medium' : ''
          }`}
          title={node.slug}
        >
          {node.title}
        </Link>
      </div>
      {hasKids && open && (
        <ul>
          {node.children.map((c) => (
            <Row
              key={c.slug}
              node={c}
              depth={depth + 1}
              activeSlug={activeSlug}
              openSet={openSet}
              toggle={toggle}
            />
          ))}
        </ul>
      )}
    </li>
  );
}

export function WikiTree({ pages, activeSlug }: Props) {
  const tree = useMemo(() => buildTree(pages), [pages]);
  const autoOpen = useMemo(() => ancestorsOf(pages, activeSlug), [pages, activeSlug]);
  const [closed, setClosed] = useState<Set<string>>(new Set());

  const openSet = useMemo(() => {
    const s = new Set<string>(autoOpen);
    // Default: roots open one level so the structure is visible at a glance.
    tree.forEach((r) => s.add(r.slug));
    closed.forEach((slug) => s.delete(slug));
    return s;
  }, [autoOpen, tree, closed]);

  const toggle = (slug: string) =>
    setClosed((prev) => {
      const next = new Set(prev);
      if (openSet.has(slug)) next.add(slug);
      else next.delete(slug);
      return next;
    });

  if (pages.length === 0) {
    return (
      <p className="px-3 py-6 text-center text-xs text-muted-foreground">No pages yet.</p>
    );
  }

  return (
    <ul className="p-1">
      {tree.map((n) => (
        <Row key={n.slug} node={n} depth={0} activeSlug={activeSlug} openSet={openSet} toggle={toggle} />
      ))}
    </ul>
  );
}
