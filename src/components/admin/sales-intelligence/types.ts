export interface ResearchResult {
  success: boolean;
  company: { id?: string; name: string; domain?: string };
  contacts: Array<{
    id: string; email: string; name?: string;
    /** From Hunter's domain search — lets the seller choose targets on WHO, not just an address. */
    position?: string | null;
    seniority?: string | null;
    confidence?: number | null;
    type?: string | null;
  }>;
  hunter_contacts_found: number;
  questions_and_answers: Array<{ question: string; answer: string; relevance_score: number }>;
  company_summary: {
    name?: string;
    industry?: string;
    size_estimate?: string;
    main_offerings?: string[];
    potential_pain_points?: string[];
  };
  error?: string;
}

export interface FitAnalysisResult {
  success: boolean;
  fit_score: number;
  /**
   * True when FlowPilot reasoned the score against the ICP; false when the
   * deterministic data-signal fallback produced it. The fallback counts
   * signals (website/domain/industry/size/enriched) — a COMPLETE company row
   * scores "100" while saying nothing about fit. The card must never present
   * that as an assessment.
   */
  ai_scored?: boolean;
  fit_advice: string;
  problem_mapping: Array<{ prospect_problem: string; our_solution: string }>;
  introduction_letter: string;
  email_subject: string;
  decision_maker: {
    email: string;
    confidence: number;
    first_name: string;
    last_name: string;
    position: string;
  } | null;
  leads_updated: number;
}
