/**
 * Shared collection (money-in) reconciliation for Lipila.
 *
 * WHY THIS FILE EXISTS
 *   Until 2026-10 the ONLY way a `coa_payments` row could reach a confirmed
 *   state was the Lipila webhook. That made a webhook the single point of
 *   failure for real money:
 *
 *     - app killed during the PIN prompt (routine on Android)
 *     - phone offline, or the user simply closes the sheet
 *     - webhook delivery delayed, dropped or rejected by a proxy
 *
 *   In every one of those cases the money had left the payer but the row sat
 *   `pending` forever: the church was never paid, the giver got no receipt, and
 *   admins saw a permanently-pending ledger. chisomo closed this by asking
 *   Lipila authoritatively on every poll and by running a scheduled
 *   `runWithdrawalStatusChecks` net; we had neither on the collection side.
 *
 *   `reconcileCollection()` is the single implementation both the
 *   `lipila-collect` status endpoint and the `lipila-settle` cron call, so the
 *   interactive path and the background sweep can never disagree.
 *
 * THE 90-SECOND GRACE PERIOD (do not remove)
 *   Lipila can report a collection as `failed` in the seconds immediately after
 *   the USSD prompt is dispatched - BEFORE the payer has entered their PIN.
 *   Treating that as terminal tells the user their payment failed while their
 *   PIN prompt is still on screen; if they then complete the ORIGINAL prompt
 *   they are charged for a payment the app already declared dead. chisomo
 *   handles this at src/index.ts:3079 with an explicit comment. We match it.
 */

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { settleReference, enqueueChurchAutoPayouts } from "./settlement.ts";

/** Statuses that mean "the money definitively arrived". */
export const CONFIRMED_STATUSES = [
  "successful",
  "paid",
  "completed",
  "settled",
  "success",
  "approved",
  "accepted",
  "confirmed",
];

/** Statuses that mean "the money definitively did not arrive". */
export const DECLINED_STATUSES = [
  "failed",
  "cancelled",
  "canceled",
  "rejected",
  "declined",
  "error",
  "expired",
];

/**
 * How long after collection creation we refuse to believe a provider failure.
 * Matches chisomo. See the file header for why this matters.
 */
export const FAILURE_GRACE_SECONDS = 90;

export type CollectionOutcome =
  | "confirmed"
  | "declined"
  | "pending"
  | "unknown"
  | "too_early"
  | "missing_row";

/** Resolves the API base for either Lipila key flavour. */
export function lipilaBaseUrl(apiKey: string): string {
  return apiKey.startsWith("lsk_")
    ? "https://blz.lipila.io/api"
    : "https://api.lipila.dev/api";
}

/**
 * Pulls a normalised status out of Lipila's check-status response.
 *
 * Lipila is not consistent about where it puts the status, and the shape has
 * changed across endpoints, so this deliberately probes several known paths
 * rather than trusting one.
 */
export function normaliseProviderStatus(payload: unknown): string {
  const raw = (payload ?? {}) as Record<string, unknown>;
  const tx =
    (raw?.data as Record<string, unknown> | undefined) ??
    (raw?.transaction as Record<string, unknown> | undefined) ??
    raw;
  const candidate = [
    (tx as Record<string, unknown>)?.["status"],
    raw?.["status"],
    (tx as Record<string, unknown>)?.["transactionStatus"],
    raw?.["transactionStatus"],
    ((raw?.data as Record<string, unknown> | undefined) ?? {})?.["status"],
  ].find((s) => typeof s === "string");
  return candidate?.toString().toLowerCase().trim() ?? "";
}

/** Reads the payer's phone / network out of a provider payload, if present. */
export function providerIdentity(payload: unknown): {
  phone: string | null;
  network: string | null;
} {
  const raw = (payload ?? {}) as Record<string, unknown>;
  const tx =
    (raw?.data as Record<string, unknown> | undefined) ??
    (raw?.transaction as Record<string, unknown> | undefined) ??
    raw;
  const phone = tx?.["accountNumber"] ?? raw?.["accountNumber"] ?? null;
  const network = tx?.["paymentType"] ?? raw?.["paymentType"] ?? null;
  return {
    phone: typeof phone === "string" ? phone : null,
    network: typeof network === "string" ? network : null,
  };
}

/**
 * Asks Lipila directly whether a collection landed.
 *
 * `kind` selects the endpoint family: mobile money collections and card
 * collections have separate status endpoints, and querying the wrong one
 * returns 404 - which is why card payments previously had NO working
 * reconciliation path at all.
 */
export async function queryProviderStatus(
  apiKey: string,
  reference: string,
  kind: "momo" | "card" = "momo",
): Promise<{ httpStatus: number; status: string; payload: unknown }> {
  const base = lipilaBaseUrl(apiKey);
  const ref = encodeURIComponent(reference);
  const candidates = kind === "card"
    ? [
      `${base}/v1/collections/card/check-status?referenceId=${ref}`,
      `${base}/v1/collections/card/${reference}`,
    ]
    : [
      // Primary, documented endpoint (this is the one chisomo uses).
      `${base}/v1/collections/check-status?referenceId=${ref}`,
      `${base}/v1/collections/mobile-money/status/${reference}`,
      `${base}/v1/collections/mobile-money/${reference}`,
    ];

  let resp: Response | null = null;
  let payload: unknown = null;
  for (const candidate of candidates) {
    try {
      resp = await fetch(candidate, {
        headers: { "x-api-key": apiKey, "accept": "application/json" },
      });
    } catch (err) {
      console.warn(`[reconcile] provider fetch failed for ${candidate}: ${err}`);
      break;
    }
    // Only fall through to the next shape on a genuine 404; any other status
    // (401/429/5xx) is a real answer and retrying other shapes just adds latency.
    if (resp.ok || resp.status !== 404) break;
  }

  try {
    payload = await resp?.json();
  } catch {
    payload = null;
  }
  return {
    httpStatus: resp?.status ?? 500,
    status: normaliseProviderStatus(payload),
    payload,
  };
}

/**
 * The single reconciliation routine. Idempotent and safe to call from both an
 * interactive request and the cron.
 *
 * On a confirmed collection it writes `settled` and runs settlement. On a
 * provider failure it writes `failed` - but only once the grace period has
 * elapsed, so a transient failure during PIN entry never destroys a payment
 * that is about to succeed.
 */
export async function reconcileCollection(
  supabase: SupabaseClient,
  reference: string,
  opts: {
    apiKey?: string;
    kind?: "momo" | "card";
    /** Override the grace window (tests). */
    graceSeconds?: number;
    /** Run settlement + church payout enqueue after confirming. */
    runSettlement?: boolean;
  } = {},
): Promise<{ outcome: CollectionOutcome; status: string }> {
  const grace = opts.graceSeconds ?? FAILURE_GRACE_SECONDS;

  const { data: payment } = await supabase
    .from("coa_payments")
    .select("id, status, created_at")
    .eq("payment_ref", reference)
    .maybeSingle();

  if (!payment) return { outcome: "missing_row", status: "" };

  // Already terminal - nothing to reconcile, and re-asking the provider would
  // burn a metered API call on every cron tick forever.
  const current = String(payment.status ?? "").toLowerCase();
  if (
    CONFIRMED_STATUSES.includes(current) ||
    DECLINED_STATUSES.includes(current)
  ) {
    return {
      outcome: CONFIRMED_STATUSES.includes(current) ? "confirmed" : "declined",
      status: current,
    };
  }

  const apiKey = opts.apiKey ?? Deno.env.get("LIPILA_API_KEY");
  if (!apiKey) return { outcome: "unknown", status: "" };

  const { httpStatus, status, payload } = await queryProviderStatus(
    apiKey,
    reference,
    opts.kind ?? "momo",
  );

  // A 404 from every candidate shape means "no such collection at the
  // provider" - which for a genuinely-pending prompt is expected, not a decline.
  if (httpStatus === 404) return { outcome: "pending", status: "" };

  if (CONFIRMED_STATUSES.includes(status)) {
    const { phone, network } = providerIdentity(payload);
    const now = new Date().toISOString();
    // NOTE: we deliberately do NOT write `webhook_idempotency` here. That column
    // is the webhook's dedup key (`lipila-<ref>`); overwriting it with
    // `lipila-status-<ref>` destroys the key the column exists for. Dedup is
    // preserved by the payment_ref lookup plus the terminal-status guard above.
    const { error } = await supabase
      .from("coa_payments")
      .update({
        status: "settled",
        settled_at: now,
        ...(phone ? { phone_number: phone } : {}),
        ...(network ? { network } : {}),
        updated_at: now,
      })
      .eq("payment_ref", reference)
      .in("status", ["pending", "initiated", "processing", ""]);
    if (error) {
      console.error(`[reconcile] failed to settle ${reference}: ${error.message}`);
      return { outcome: "unknown", status };
    }

    if (opts.runSettlement !== false) {
      try {
        await settleReference(supabase, reference);
        await enqueueChurchAutoPayouts(supabase);
      } catch (settleErr) {
        // Settlement failures must never lose the confirmation we just wrote -
        // the cron retries on the next tick.
        console.error(`[reconcile] settlement failed for ${reference}: ${settleErr}`);
      }
    }
    return { outcome: "confirmed", status };
  }

  if (DECLINED_STATUSES.includes(status)) {
    const ageSeconds = payment.created_at
      ? (Date.now() - new Date(payment.created_at).getTime()) / 1000
      : Number.POSITIVE_INFINITY;
    if (ageSeconds < grace) {
      // Too early to call it. See the grace-period note in the file header.
      return { outcome: "too_early", status };
    }
    const { error } = await supabase
      .from("coa_payments")
      .update({
        status: "failed",
        updated_at: new Date().toISOString(),
      })
      .eq("payment_ref", reference)
      .eq("status", "pending");
    if (error) {
      console.error(`[reconcile] failed to mark ${reference} declined: ${error.message}`);
      return { outcome: "unknown", status };
    }
    return { outcome: "declined", status };
  }

  return { outcome: "pending", status };
}

/**
 * Cron-side sweep: reconcile every collection that has been pending long enough
 * to be decidable.
 *
 * This is the piece that makes reconciliation independent of the client app. The
 * Flutter `status` poll only helps while the app is alive; if the phone is killed
 * mid-PIN nothing was asking Lipila, and the row was stranded. This runs from
 * the `lps-settle` pg_cron job instead.
 *
 * Deliberately bounded (default 50) so one tick cannot fan out into an unbounded
 * number of metered partner API calls.
 */
export async function reconcilePendingCollections(
  supabase: SupabaseClient,
  opts: { limit?: number; kind?: "momo" | "card"; apiKey?: string } = {},
): Promise<{ checked: number; confirmed: number; declined: number; skipped: number }> {
  const limit = opts.limit ?? 50;
  const apiKey = opts.apiKey ?? Deno.env.get("LIPILA_API_KEY");
  if (!apiKey) {
    console.warn("[reconcile] LIPILA_API_KEY not set; collection sweep skipped");
    return { checked: 0, confirmed: 0, declined: 0, skipped: 0 };
  }

  // Anything younger than the grace window is undecidable; selecting only
  // older rows means we never even call the provider for a payment that might
  // still be mid-PIN.
  const { data: rows, error } = await supabase
    .from("coa_payments")
    .select("payment_ref, status")
    .eq("status", "pending")
    .lt("created_at", new Date(Date.now() - FAILURE_GRACE_SECONDS * 1000).toISOString())
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) {
    console.error(`[reconcile] could not list pending collections: ${error.message}`);
    return { checked: 0, confirmed: 0, declined: 0, skipped: 0 };
  }

  let confirmed = 0;
  let declined = 0;
  let skipped = 0;
  for (const row of rows ?? []) {
    const reference = String(row.payment_ref ?? "");
    if (!reference) {
      skipped++;
      continue;
    }
    try {
      const { outcome } = await reconcileCollection(supabase, reference, {
        apiKey,
        kind: opts.kind ?? "momo",
      });
      if (outcome === "confirmed") confirmed++;
      else if (outcome === "declined") declined++;
      else if (outcome === "pending") skipped++;
    } catch (err) {
      console.error(`[reconcile] ${reference} threw: ${err}`);
      skipped++;
    }
  }

  console.log(
    `[reconcile] collections: checked=${rows?.length ?? 0} confirmed=${confirmed} declined=${declined} skipped=${skipped}`,
  );
  return { checked: rows?.length ?? 0, confirmed, declined, skipped };
}
