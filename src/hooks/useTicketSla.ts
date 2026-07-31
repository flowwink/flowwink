import { useMemo } from 'react';
import { useSlaPolicies, useSlaViolations } from '@/hooks/useSla';
import type { Ticket } from '@/hooks/useTickets';

export type TicketSlaState = 'breached' | 'due_soon' | 'ok' | 'none';

export interface TicketSlaStatus {
  state: TicketSlaState;
  dueAt: string | null;
  /** Short human label, e.g. "2h left" or "Breached 3h ago". */
  label: string;
  /** Metric the status is derived from (resolution / first_response). */
  metric?: string;
}

const OPEN_STATUSES = new Set(['new', 'open', 'in_progress', 'waiting']);

function humanizeMinutes(mins: number) {
  const m = Math.abs(Math.round(mins));
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 48) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

/**
 * Derives a per-ticket SLA status by combining the authoritative SLA Monitor
 * violations (entity_type = 'ticket') with a countdown from the ticket's own
 * `sla_deadline`, falling back to the active ticket resolution policy.
 */
export function useTicketSlaMap(tickets: Ticket[]) {
  const { data: policies = [] } = useSlaPolicies();
  const { data: violations = [] } = useSlaViolations({ resolved: false, entity_type: 'ticket' });

  return useMemo(() => {
    const breachedIds = new Map<string, { metric: string; minutes: number }>();
    violations.forEach((v) => {
      if (!breachedIds.has(v.entity_id)) {
        breachedIds.set(v.entity_id, { metric: v.metric, minutes: v.actual_minutes - v.threshold_minutes });
      }
    });

    const ticketPolicies = policies.filter(
      (p) => p.enabled && p.entity_type === 'ticket' && p.metric === 'resolution'
    );

    const map = new Map<string, TicketSlaStatus>();
    const now = Date.now();

    tickets.forEach((t) => {
      const violation = breachedIds.get(t.id);
      if (violation) {
        map.set(t.id, {
          state: 'breached',
          dueAt: null,
          metric: violation.metric,
          label: `Breached by ${humanizeMinutes(violation.minutes)}`,
        });
        return;
      }

      if (!OPEN_STATUSES.has(t.status)) {
        map.set(t.id, { state: 'none', dueAt: null, label: 'Met' });
        return;
      }

      let dueAt: number | null = t.sla_deadline ? new Date(t.sla_deadline).getTime() : null;
      let metric = 'resolution';
      if (!dueAt && ticketPolicies.length > 0) {
        const policy =
          ticketPolicies.find((p) => p.priority === t.priority) ?? ticketPolicies[0];
        dueAt = new Date(t.created_at).getTime() + policy.threshold_minutes * 60_000;
        metric = policy.metric;
      }

      if (!dueAt) {
        map.set(t.id, { state: 'none', dueAt: null, label: 'No SLA' });
        return;
      }

      const minutesLeft = (dueAt - now) / 60_000;
      const iso = new Date(dueAt).toISOString();
      if (minutesLeft <= 0) {
        map.set(t.id, {
          state: 'breached',
          dueAt: iso,
          metric,
          label: `Overdue ${humanizeMinutes(minutesLeft)}`,
        });
      } else if (minutesLeft <= 120) {
        map.set(t.id, {
          state: 'due_soon',
          dueAt: iso,
          metric,
          label: `${humanizeMinutes(minutesLeft)} left`,
        });
      } else {
        map.set(t.id, {
          state: 'ok',
          dueAt: iso,
          metric,
          label: `${humanizeMinutes(minutesLeft)} left`,
        });
      }
    });

    return map;
  }, [tickets, policies, violations]);
}
