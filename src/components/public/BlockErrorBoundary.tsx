import { Component, type ErrorInfo, type ReactNode } from 'react';
import { logger } from '@/lib/logger';

interface Props {
  /** Block type, for the log line — never rendered to visitors. */
  blockType: string;
  children: ReactNode;
}

interface State {
  failed: boolean;
}

/**
 * One bad block must not take the page with it.
 *
 * Blocks render authored data — from templates, from the editor, from agents
 * over MCP — and that data can carry values the renderer never anticipated. A
 * lookup like `sizeClasses[data.size]` returns `undefined` for an unknown key,
 * and the very next line (`s.padding`) throws a TypeError. React unmounts the
 * whole tree on an uncaught render error, so until this existed, a single
 * mistyped value on one block turned an entire customer's public page white.
 * There was no boundary anywhere in the app (verified 2026-08-13) — the sweep
 * that followed the hero-height bug found six such crash sites.
 *
 * The individual lookups are being fixed, but the guarantee has to hold for
 * the ones nobody has found yet: a block that throws is skipped, the rest of
 * the page renders, and the failure is logged rather than shown. Visitors see
 * a page missing one section, which is recoverable; they never see nothing,
 * which is not.
 */
export class BlockErrorBoundary extends Component<Props, State> {
  state: State = { failed: false };

  static getDerivedStateFromError(): State {
    return { failed: true };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // logger.error survives the production log suppression — this is exactly
    // the class of thing an operator needs to see in the console.
    logger.error(
      `[BlockRenderer] "${this.props.blockType}" block failed to render and was skipped:`,
      error.message,
      info.componentStack,
    );
  }

  render() {
    // Render nothing rather than an apology: a visitor cannot act on "this
    // section is broken", and the operator gets the console line instead.
    if (this.state.failed) return null;
    return this.props.children;
  }
}
