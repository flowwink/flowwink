import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export type TicketAssignee = {
  id: string;
  full_name: string | null;
  email: string | null;
};

export function assigneeLabel(a?: TicketAssignee | null) {
  if (!a) return "Unassigned";
  return a.full_name || a.email || "Unknown user";
}

/** Internal users that a ticket can be assigned to (owner / agent). */
export function useTicketAssignees() {
  return useQuery({
    queryKey: ["ticket-assignees"],
    queryFn: async (): Promise<TicketAssignee[]> => {
      const { data, error } = await supabase
        .from("profiles")
        .select("id, full_name, email")
        .order("full_name", { ascending: true });
      if (error) throw error;
      return (data ?? []) as TicketAssignee[];
    },
    staleTime: 5 * 60 * 1000,
  });
}
