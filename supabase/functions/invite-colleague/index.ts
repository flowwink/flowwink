// invite-colleague — email a colleague an invite that lands them, on first
// sign-in, already holding the functional role they need.
//
// The gap this closes: create-user grants the right role but forces the admin
// to set a password and hand it over; invite-employee sends a real email but
// grants writer+employee, never the functional role (sales/support/…) that
// the module matrix actually gates access on. So inviting a salesperson meant
// either sharing a password or granting the wrong roles and fixing them by
// hand. This does both right: Supabase Auth sends the invite email (the
// colleague sets their own password), and the chosen functional role is
// granted immediately — inviteUserByEmail creates the auth row now, so the
// signup trigger has already fired and we reconcile on top of it, exactly
// like create-user.
//
// Deployed with default JWT verification; the admin check is enforced here.
import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { getServiceClient, getUserClient } from "../_shared/supabase-clients.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

// Mirror of FUNCTIONAL_ROLES in src/types/cms.ts, plus admin. A guardrail test
// compares this list against that source so the two cannot drift.
const INVITABLE_ROLES = [
  "admin",
  "sales", "hr", "accounting", "support",
  "warehouse", "marketing", "purchasing", "projects",
];

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Unauthorized" }, 401);

    // Caller must be an authenticated admin.
    const admin = getServiceClient();
    const userClient = getUserClient(authHeader)!;
    const { data: userData } = await userClient.auth.getUser();
    if (!userData?.user) return json({ error: "Unauthorized" }, 401);

    const { data: isAdmin } = await admin.rpc("has_role", {
      _user_id: userData.user.id, _role: "admin",
    });
    if (!isAdmin) return json({ error: "Admin role required" }, 403);

    const { email, role, full_name } = (await req.json()) as {
      email?: string; role?: string; full_name?: string;
    };

    const cleanEmail = (email ?? "").trim().toLowerCase();
    if (!cleanEmail || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleanEmail)) {
      return json({ error: "A valid email is required." }, 400);
    }
    if (!role || !INVITABLE_ROLES.includes(role)) {
      return json({ error: `role must be one of: ${INVITABLE_ROLES.join(", ")}` }, 400);
    }

    // If the email already has an account, don't re-invite — just grant the
    // role. Re-inviting an existing user is a confusing no-op at best.
    const { data: existing } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
    const found = existing?.users?.find(
      (u) => u.email?.toLowerCase() === cleanEmail,
    );

    let userId: string;
    let status: "invited" | "granted_existing";

    if (found) {
      userId = found.id;
      status = "granted_existing";
    } else {
      // signup_type=customer so the trigger's fail-closed path runs; we
      // reconcile to the chosen role below. redirectTo lands staff in /admin.
      const redirectTo = `${req.headers.get("origin") ?? ""}/admin`;
      const { data: invited, error: inviteErr } = await admin.auth.admin.inviteUserByEmail(
        cleanEmail,
        { data: { full_name: full_name || cleanEmail, signup_type: "customer" }, redirectTo },
      );
      if (inviteErr || !invited?.user) {
        return json({ error: inviteErr?.message ?? "Invite failed" }, 500);
      }
      userId = invited.user.id;
      status = "invited";
    }

    // Reconcile roles: grant exactly the chosen role, clear anything the
    // trigger seeded (customer) — but NEVER strip admin from an existing user,
    // and never touch roles when granting to someone who already has others;
    // an admin adding a role to a colleague should not silently remove theirs.
    await admin.from("user_roles").upsert(
      { user_id: userId, role },
      { onConflict: "user_id,role" },
    );
    if (status === "invited") {
      // Fresh invite: the only pre-existing role is the trigger's customer
      // seed. Remove it so the colleague is born as exactly their function.
      await admin.from("user_roles").delete().eq("user_id", userId).eq("role", "customer");
    }

    await admin.from("audit_logs").insert({
      action: "invite_colleague",
      entity_type: "user",
      entity_id: userId,
      user_id: userData.user.id,
      metadata: { email: cleanEmail, role, status },
    });

    return json({ success: true, user_id: userId, role, status });
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }
});
