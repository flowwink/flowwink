import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { callSkill } from '@/lib/call-skill';
import { ChannelType, ContentProposal } from './useContentProposals';

interface GenerateProposalInput {
  topic: string;
  pillar_content?: string;
  target_channels: ChannelType[];
  brand_voice?: string;
  target_audience?: string;
  tone_level?: number; // 1-5 (1=formal, 5=casual)
  industry?: string;
  content_goals?: string[];
  unique_angle?: string;
  schedule_for?: string;
  /** Traceability (learning mode): which research + angle shaped this campaign. */
  source_research?: { research_id: string; topic: string; chosen_angle: string | null };
}

interface GenerateProposalResponse {
  success: boolean;
  proposal: ContentProposal;
  message: string;
  validation_issues?: string[];
}


export function useGenerateProposal() {
  const queryClient = useQueryClient();
  const [progress, setProgress] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: async (input: GenerateProposalInput): Promise<GenerateProposalResponse> => {
      setProgress('Generating content...');

      // Get user ID for proposal attribution (admin is authenticated)
      const { data: { user } } = await supabase.auth.getUser();

      // Direct skill call — same fix as useContentResearch: the model-echo
      // path silently produced empty results when the model skipped the tool.
      // A deterministic generation call has no business passing through a
      // model's mouth. (The identity/knowledge grounding lives server-side in
      // the ai-task, so nothing is lost by skipping chat-completion.)
      const envelope = await callSkill<Record<string, any>>('generate_content_proposal', input as unknown as Record<string, unknown>);
      if (envelope?.error) throw new Error(String(envelope.error));

      const generated = envelope?.result ?? envelope?.proposal ?? envelope;
      if (!generated?.channel_variants || Object.keys(generated.channel_variants).length === 0) {
        throw new Error('Generation returned no channel variants — check the AI provider under Settings and try again.');
      }

      // Persist — the ai-task only GENERATES; without this insert the content
      // evaporated on dialog close (the fan-out approves content_proposals
      // rows, so a row is the campaign).
      const { data: saved, error: saveErr } = await supabase
        .from('content_proposals')
        .insert({
          topic: input.topic,
          pillar_content: generated.pillar_content ?? input.pillar_content ?? null,
          channel_variants: generated.channel_variants,
          status: 'pending_review',
          scheduled_for: input.schedule_for ?? null,
          source_research: (input.source_research ?? null) as never,
          created_by: user?.id ?? null,
        })
        .select()
        .single();
      if (saveErr) throw new Error(`Generated but save failed: ${saveErr.message}`);

      return {
        success: true,
        proposal: saved as unknown as GenerateProposalResponse['proposal'],
        message: 'Content proposal generated',
      } as GenerateProposalResponse;
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['content-proposals'] });

      if (data.validation_issues?.length) {
        toast.success(data.message, {
          description: `Note: ${data.validation_issues.length} minor quality suggestions available`,
        });
      } else {
        toast.success(data.message || 'Content proposal generated');
      }

      setProgress(null);
    },
    onError: (error: Error) => {
      toast.error(error.message || 'Failed to generate proposal');
      setProgress(null);
    },
  });

  return {
    generateProposal: mutation.mutateAsync,
    isGenerating: mutation.isPending,
    progress,
  };
}
