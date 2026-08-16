import { useState, useEffect } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Building2, Save, Loader2, Plus, X, Globe, Sparkles } from "lucide-react";
import { toast } from "sonner";
import type { Json } from "@/integrations/supabase/types";

interface CompanyProfile {
  company_name: string;
  about_us: string;
  services: Record<string, string>;
  delivered_value: string;
  clients: string;
  client_testimonials: string;
  target_industries: string[];
  differentiators: string[];
  // Sales-specific fields
  value_proposition: string;
  icp: string;
  /** How claims are made, not what is claimed — e.g. "we describe our services
   * precisely; we never interpret regulations on a customer's behalf". Injected
   * into every outward AI surface as a writing rule. */
  claim_stance: string;
  competitors: string;
  pricing_notes: string;
  industry: string;
  // Contact info (may be auto-extracted)
  contact_email: string;
  contact_phone: string;
  address: string;
}

const defaultProfile: CompanyProfile = {
  company_name: "",
  about_us: "",
  services: {},
  delivered_value: "",
  clients: "",
  client_testimonials: "",
  target_industries: [],
  differentiators: [],
  value_proposition: "",
  icp: "",
  claim_stance: "",
  competitors: "",
  pricing_notes: "",
  industry: "",
  contact_email: "",
  contact_phone: "",
  address: "",
};

export function CompanyProfileCard() {
  const queryClient = useQueryClient();
  const [profile, setProfile] = useState<CompanyProfile>(defaultProfile);
  const [newServiceName, setNewServiceName] = useState("");
  const [newServiceDesc, setNewServiceDesc] = useState("");
  const [newIndustry, setNewIndustry] = useState("");
  const [newDifferentiator, setNewDifferentiator] = useState("");
  const [enrichUrl, setEnrichUrl] = useState("");
  const [isEnriching, setIsEnriching] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ["site-settings", "company_profile"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("site_settings")
        .select("value")
        .eq("key", "company_profile")
        .maybeSingle();
      if (error) throw error;
      return (data?.value as unknown as CompanyProfile) || defaultProfile;
    },
    staleTime: 1000 * 60 * 5,
  });

  useEffect(() => {
    if (data) setProfile({ ...defaultProfile, ...data });
  }, [data]);

  const saveMutation = useMutation({
    mutationFn: async (p: CompanyProfile) => {
      const { data: existing } = await supabase
        .from("site_settings")
        .select("id")
        .eq("key", "company_profile")
        .maybeSingle();

      const jsonValue = p as unknown as Json;

      if (existing) {
        const { error } = await supabase
          .from("site_settings")
          .update({ value: jsonValue, updated_at: new Date().toISOString() })
          .eq("key", "company_profile");
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from("site_settings")
          .insert({ key: "company_profile", value: jsonValue });
        if (error) throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["site-settings", "company_profile"] });
      toast.success("Company profile saved");
    },
    onError: (err) => {
      toast.error(`Failed to save: ${err instanceof Error ? err.message : "Unknown error"}`);
    },
  });

  const handleEnrich = async () => {
    if (!enrichUrl.trim()) return;
    setIsEnriching(true);
    try {
      const { data, error } = await supabase.functions.invoke("migrate-page", {
        body: { url: enrichUrl.trim() },
      });
      if (error) throw error;
      if (data?.companyProfile) {
        const extracted = data.companyProfile as Record<string, unknown>;
        setProfile(prev => {
          const merged = { ...prev };
          for (const [key, val] of Object.entries(extracted)) {
            const currentVal = (prev as unknown as Record<string, unknown>)[key];
            if (val && String(val).trim() && (!currentVal || !String(currentVal).trim())) {
              (merged as unknown as Record<string, unknown>)[key] = val;
            }
          }
          return merged;
        });
        toast.success("Company data extracted — review and save");
      } else {
        toast.info("No company data could be extracted from this page");
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Enrichment failed");
    } finally {
      setIsEnriching(false);
    }
  };

  const update = (field: keyof CompanyProfile, value: any) => {
    setProfile((prev) => ({ ...prev, [field]: value }));
  };

  const addService = () => {
    if (!newServiceName.trim()) return;
    update("services", { ...profile.services, [newServiceName.trim()]: newServiceDesc.trim() });
    setNewServiceName("");
    setNewServiceDesc("");
  };

  const removeService = (name: string) => {
    const next = { ...profile.services };
    delete next[name];
    update("services", next);
  };

  const addTag = (field: "target_industries" | "differentiators", value: string, setter: (v: string) => void) => {
    if (!value.trim()) return;
    update(field, [...(profile[field] || []), value.trim()]);
    setter("");
  };

  const removeTag = (field: "target_industries" | "differentiators", index: number) => {
    update(field, (profile[field] || []).filter((_, i) => i !== index));
  };

  const filledFields = [
    profile.company_name,
    profile.about_us,
    Object.keys(profile.services).length > 0,
    profile.delivered_value,
    profile.target_industries.length > 0,
    profile.value_proposition,
    profile.icp,
  ].filter(Boolean).length;

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Company Profile</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="animate-pulse space-y-3">
            <div className="h-8 bg-muted rounded" />
            <div className="h-20 bg-muted rounded" />
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="md:col-span-2">
      <CardHeader className="pb-3">
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-lg bg-primary/10">
              <Building2 className="h-5 w-5 text-primary" />
            </div>
            <div>
              <CardTitle className="text-base flex items-center gap-2">
                Company Profile
                <Badge variant={filledFields >= 5 ? "default" : "outline"} className="text-xs">
                  {filledFields}/7 sections
                </Badge>
              </CardTitle>
              <CardDescription>
                Unified business context used by Sales Intelligence, Chat AI, FlowPilot, and external agents
              </CardDescription>
            </div>
          </div>
          <Button
            size="sm"
            onClick={() => saveMutation.mutate(profile)}
            disabled={saveMutation.isPending}
            className="gap-1.5"
          >
            {saveMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
            Save
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-8">
        {/* Enrich from Website */}
        <div className="p-3 rounded-lg border border-dashed bg-muted/30 space-y-2">
          <Label className="text-xs font-medium flex items-center gap-1.5">
            <Globe className="h-3.5 w-3.5" />
            Enrich from Website
          </Label>
          <div className="flex gap-2">
            <Input
              value={enrichUrl}
              onChange={(e) => setEnrichUrl(e.target.value)}
              placeholder="https://yourcompany.com"
              className="h-8 text-sm"
              onKeyDown={(e) => e.key === "Enter" && handleEnrich()}
            />
            <Button
              variant="outline"
              size="sm"
              className="h-8 gap-1.5 shrink-0"
              onClick={handleEnrich}
              disabled={isEnriching || !enrichUrl.trim()}
            >
              {isEnriching ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Sparkles className="h-3.5 w-3.5" />}
              Enrich
            </Button>
          </div>
          <p className="text-[11px] text-muted-foreground">
            AI will extract company data from your website. Existing fields won't be overwritten.
          </p>
        </div>

        {/* ── Basics ───────────────────────────────── */}
        <Section title="Basics" hint="Identity facts used everywhere the company is named.">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Company Name" htmlFor="cp-name">
              <Input
                id="cp-name"
                value={profile.company_name}
                onChange={(e) => update("company_name", e.target.value)}
                placeholder="Acme Consulting AB"
                className="h-9"
              />
            </Field>
            <Field label="Industry" htmlFor="cp-industry">
              <Input
                id="cp-industry"
                value={profile.industry}
                onChange={(e) => update("industry", e.target.value)}
                placeholder="Digital Agency, SaaS, Consulting..."
                className="h-9"
              />
            </Field>
          </div>

          <Field
            label="About Us"
            htmlFor="cp-about"
            hint="The paragraph the AI reuses when introducing you."
            value={profile.about_us}
          >
            <Textarea
              id="cp-about"
              value={profile.about_us}
              onChange={(e) => update("about_us", e.target.value)}
              placeholder="Brief description of your company, mission, and what you do..."
              className="min-h-[140px] resize-y leading-relaxed"
            />
          </Field>
        </Section>

        {/* ── Positioning ──────────────────────────── */}
        <Section title="Positioning" hint="How you win — feeds Sales Intelligence and outreach drafts.">
          <div className="grid gap-4 lg:grid-cols-2">
            <Field
              label="Value Proposition"
              htmlFor="cp-vp"
              value={profile.value_proposition}
            >
              <Textarea
                id="cp-vp"
                value={profile.value_proposition}
                onChange={(e) => update("value_proposition", e.target.value)}
                placeholder="What unique value do you deliver to clients?"
                className="min-h-[120px] resize-y leading-relaxed"
              />
            </Field>
            <Field
              label="Ideal Customer Profile"
              htmlFor="cp-icp"
              hint="Size, industry, buying trigger, pain."
              value={profile.icp}
            >
              <Textarea
                id="cp-icp"
                value={profile.icp}
                onChange={(e) => update("icp", e.target.value)}
                placeholder="Describe your ideal customer: size, industry, challenges..."
                className="min-h-[120px] resize-y leading-relaxed"
              />
            </Field>
          </div>

          <Field
            label="Claim stance"
            htmlFor="cp-claim-stance"
            hint="How claims are made — not what is claimed. Every outward AI surface writes under this rule."
            value={profile.claim_stance}
          >
            <Textarea
              id="cp-claim-stance"
              value={profile.claim_stance}
              onChange={(e) => update("claim_stance", e.target.value)}
              placeholder={'e.g. "We describe what our services do, precisely enough for the customer and their advisers to assess. We never interpret what regulations require of a specific organization, and we never state or imply that buying us makes anyone compliant."'}
              className="min-h-[120px] resize-y leading-relaxed"
            />
          </Field>

          <Field
            label="Delivered Value"
            htmlFor="cp-value"
            hint="Concrete, measurable outcomes — the most quoted field in proposals."
            value={profile.delivered_value}
          >
            <Textarea
              id="cp-value"
              value={profile.delivered_value}
              onChange={(e) => update("delivered_value", e.target.value)}
              placeholder="What measurable outcomes do you deliver? E.g. '30% increase in lead conversion'..."
              className="min-h-[120px] resize-y leading-relaxed"
            />
          </Field>

          <div className="space-y-4 sm:grid sm:grid-cols-2 sm:gap-4 sm:space-y-0">
            <div className="space-y-2">
              <Label className="text-xs font-medium">Target Industries</Label>
              {(profile.target_industries || []).length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {(profile.target_industries || []).map((ind, i) => (
                    <Badge key={i} variant="secondary" className="gap-1 text-xs">
                      {ind}
                      <button onClick={() => removeTag("target_industries", i)} className="ml-0.5 hover:text-destructive">
                        <X className="h-2.5 w-2.5" />
                      </button>
                    </Badge>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <Input
                  value={newIndustry}
                  onChange={(e) => setNewIndustry(e.target.value)}
                  placeholder="Add industry..."
                  className="h-8 text-sm"
                  onKeyDown={(e) => e.key === "Enter" && addTag("target_industries", newIndustry, setNewIndustry)}
                />
                <Button variant="outline" size="sm" className="h-8 px-2 shrink-0" onClick={() => addTag("target_industries", newIndustry, setNewIndustry)}>
                  <Plus className="h-3.5 w-3.5" />
                </Button>
              </div>
            </div>

            <div className="space-y-2">
              <Label className="text-xs font-medium">Key Differentiators</Label>
              {(profile.differentiators || []).length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {(profile.differentiators || []).map((diff, i) => (
                    <Badge key={i} variant="secondary" className="gap-1 text-xs">
                      {diff}
                      <button onClick={() => removeTag("differentiators", i)} className="ml-0.5 hover:text-destructive">
                        <X className="h-2.5 w-2.5" />
                      </button>
                    </Badge>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <Input
                  value={newDifferentiator}
                  onChange={(e) => setNewDifferentiator(e.target.value)}
                  placeholder="Add differentiator..."
                  className="h-8 text-sm"
                  onKeyDown={(e) => e.key === "Enter" && addTag("differentiators", newDifferentiator, setNewDifferentiator)}
                />
                <Button variant="outline" size="sm" className="h-8 px-2 shrink-0" onClick={() => addTag("differentiators", newDifferentiator, setNewDifferentiator)}>
                  <Plus className="h-3.5 w-3.5" />
                </Button>
              </div>
            </div>
          </div>
        </Section>

        {/* ── Offering ─────────────────────────────── */}
        <Section title="Offering" hint="Services the agent may reference, quote and sell.">
          <div className="space-y-2">
            {Object.entries(profile.services).length > 0 && (
              <div className="grid gap-1.5 sm:grid-cols-2">
                {Object.entries(profile.services).map(([name, desc]) => (
                  <div key={name} className="flex items-start gap-2 p-2.5 rounded-md border bg-muted/40">
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium">{name}</p>
                      {desc && <p className="text-xs text-muted-foreground whitespace-pre-wrap break-words">{desc}</p>}
                    </div>
                    <Button variant="ghost" size="sm" className="h-6 w-6 p-0 shrink-0" onClick={() => removeService(name)}>
                      <X className="h-3 w-3" />
                    </Button>
                  </div>
                ))}
              </div>
            )}
            <div className="flex flex-col gap-2 sm:flex-row">
              <Input
                value={newServiceName}
                onChange={(e) => setNewServiceName(e.target.value)}
                placeholder="Service name"
                className="h-8 text-sm sm:w-1/3"
                onKeyDown={(e) => e.key === "Enter" && addService()}
              />
              <div className="flex flex-1 gap-2">
                <Input
                  value={newServiceDesc}
                  onChange={(e) => setNewServiceDesc(e.target.value)}
                  placeholder="Brief description"
                  className="h-8 text-sm flex-1"
                  onKeyDown={(e) => e.key === "Enter" && addService()}
                />
                <Button variant="outline" size="sm" className="h-8 px-2 shrink-0" onClick={addService}>
                  <Plus className="h-3.5 w-3.5" />
                </Button>
              </div>
            </div>
          </div>

          <Field
            label="Pricing Strategy"
            htmlFor="cp-pricing"
            hint="Model and ranges — never shown publicly, only used for internal reasoning."
            value={profile.pricing_notes}
          >
            <Textarea
              id="cp-pricing"
              value={profile.pricing_notes}
              onChange={(e) => update("pricing_notes", e.target.value)}
              placeholder="Pricing model, ranges, or strategy notes..."
              className="min-h-[110px] resize-y leading-relaxed"
            />
          </Field>
        </Section>

        {/* ── Proof ────────────────────────────────── */}
        <Section title="Proof" hint="Social proof the agent can quote in content and outreach.">
          <div className="grid gap-4 lg:grid-cols-2">
            <Field label="Notable Clients" htmlFor="cp-clients">
              <Input
                id="cp-clients"
                value={profile.clients}
                onChange={(e) => update("clients", e.target.value)}
                placeholder="Volvo, IKEA, Spotify..."
                className="h-9"
              />
              <div className="pt-4">
                <Label htmlFor="cp-competitors" className="text-xs font-medium">Competitors</Label>
                <Input
                  id="cp-competitors"
                  value={profile.competitors}
                  onChange={(e) => update("competitors", e.target.value)}
                  placeholder="Competitor A, Competitor B..."
                  className="h-9 mt-1.5"
                />
              </div>
            </Field>
            <Field
              label="Client Testimonials"
              htmlFor="cp-testimonials"
              value={profile.client_testimonials}
            >
              <Textarea
                id="cp-testimonials"
                value={profile.client_testimonials}
                onChange={(e) => update("client_testimonials", e.target.value)}
                placeholder="Short quotes from happy clients..."
                className="min-h-[140px] resize-y leading-relaxed"
              />
            </Field>
          </div>
        </Section>

        {/* ── Contact ──────────────────────────────── */}
        <Section title="Contact" hint="Used in signatures, footers and structured data.">
          <div className="grid gap-4 sm:grid-cols-3">
            <Field label="Contact Email" htmlFor="cp-email">
              <Input
                id="cp-email"
                value={profile.contact_email}
                onChange={(e) => update("contact_email", e.target.value)}
                placeholder="info@company.com"
                className="h-9"
              />
            </Field>
            <Field label="Contact Phone" htmlFor="cp-phone">
              <Input
                id="cp-phone"
                value={profile.contact_phone}
                onChange={(e) => update("contact_phone", e.target.value)}
                placeholder="+46 8 123 45 67"
                className="h-9"
              />
            </Field>
            <Field label="Address" htmlFor="cp-address">
              <Input
                id="cp-address"
                value={profile.address}
                onChange={(e) => update("address", e.target.value)}
                placeholder="Street, City"
                className="h-9"
              />
            </Field>
          </div>
        </Section>

        <div className="flex justify-end border-t pt-4">
          <Button
            onClick={() => saveMutation.mutate(profile)}
            disabled={saveMutation.isPending}
            className="gap-1.5"
          >
            {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            Save Business Identity
          </Button>
        </div>
      </CardContent>

    </Card>
  );
}

function Section({ title, hint, children }: { title: string; hint?: string; children: React.ReactNode }) {
  return (
    <section className="space-y-4">
      <div className="flex items-baseline gap-2 border-b pb-2">
        <h3 className="text-sm font-semibold tracking-tight">{title}</h3>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </div>
      {children}
    </section>
  );
}

function Field({
  label,
  htmlFor,
  hint,
  value,
  children,
}: {
  label: string;
  htmlFor?: string;
  hint?: string;
  value?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between gap-2">
        <Label htmlFor={htmlFor} className="text-xs font-medium">{label}</Label>
        {typeof value === "string" && value.length > 0 && (
          <span className="text-[10px] text-muted-foreground tabular-nums">{value.length} chars</span>
        )}
      </div>
      {children}
      {hint && <p className="text-[11px] text-muted-foreground">{hint}</p>}
    </div>
  );
}
