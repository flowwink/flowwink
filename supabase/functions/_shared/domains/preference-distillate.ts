// Preference distillate — learning mode's third leg (#90).
//
// The choice history in content_research (chosen_angle / rejected_angles /
// chosen_hooks) is the only signal that says something about THIS company's
// taste rather than the model's priors. But raw history must never enter a
// prompt — that is the context-window explosion Magnus explicitly ruled out.
// So: distill to a few hundred characters and inject like the identity block.
//
// Deterministic on purpose (v1): the distillate is counted, not paraphrased.
// An AI-written summary of preferences would itself be a model's opinion about
// the human's opinions; a tally is evidence. If the tally proves too blunt,
// an AI pass can be layered on later — the injection point won't move.
//
// Silent when there is nothing to say: fewer than MIN_CHOICES stamped choices
// returns '' and the prompt is exactly what it was before learning mode.

// deno-lint-ignore no-explicit-any
type Db = any;

const MIN_CHOICES = 3;
const LOOKBACK_ROWS = 25;

export async function loadPreferenceDistillate(supabase: Db): Promise<string> {
  try {
    const { data } = await supabase
      .from('content_research')
      .select('chosen_angle, rejected_angles, chosen_hooks, chosen_at')
      .not('chosen_at', 'is', null)
      .order('chosen_at', { ascending: false })
      .limit(LOOKBACK_ROWS);

    const rows = (data ?? []) as Array<{
      chosen_angle: string | null;
      rejected_angles: string[] | null;
      chosen_hooks: string[] | null;
    }>;
    if (rows.length < MIN_CHOICES) return '';

    const chosen = rows.map((r) => r.chosen_angle).filter(Boolean) as string[];
    const rejected = rows.flatMap((r) => r.rejected_angles ?? []).filter(Boolean);
    const hooks = rows.flatMap((r) => r.chosen_hooks ?? []).filter(Boolean);
    if (!chosen.length) return '';

    // Recent picks verbatim (they carry the pattern better than any label),
    // rejected angles only as a compact tail. Hard budget keeps the promise.
    const pick = (xs: string[], n: number) => [...new Set(xs)].slice(0, n);
    const lines = [
      `\n\n## EDITORIAL TASTE (distilled from ${rows.length} past angle choices — bias toward this, never copy it)`,
      `Angles this team picks: ${pick(chosen, 5).join(' | ')}`,
      rejected.length ? `Angles they reject: ${pick(rejected, 5).join(' | ')}` : '',
      hooks.length ? `Hook styles they keep: ${pick(hooks, 3).join(' | ')}` : '',
    ].filter(Boolean);

    const block = lines.join('\n');
    return block.length > 700 ? block.slice(0, 700) : block;
  } catch {
    // Learning is a bonus, never a dependency: no distillate, unchanged prompt.
    return '';
  }
}
