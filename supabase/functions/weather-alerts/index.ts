// ============================================================================
// weather-alerts — per-user weather alerts (opt-in, thresholds, quiet hours)
//
// Called every 30 minutes by pg_cron with the shared cron secret. It is the
// only place a forecast HTTP request is made: an Edge Function has a real
// `fetch`, proper timeouts and testable error handling, which plpgsql/pg_net
// does not give you. The DATABASE keeps the preferences, the once-per-day
// dedupe, and the authoritative decision to send.
//
// PRIVACY / SAFETY
//   * Opt-in only. A user with no row is never evaluated, never contacted.
//   * Quiet hours are enforced here AND in the query, so a bug in the app
//     cannot spam somebody at 3am.
//   * One alert per user per LOCAL day. The cron runs twice an hour; a user
//     still gets at most one alert.
//   * A forecast failure is swallowed per-location and never consumes the
//     user's single daily alert, so a flaky network cannot make them miss it.
//   * Coordinates come from the user's own saved preference (their profile /
//     their church). Nothing is inferred from anyone's location history.
//
//   Actions: `sweep` (cron), `preview` (staff dry run — sends nothing)
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL =
  Deno.env.get("SUPABASE_URL") ??
  "https://daboihiudmglwhdfvsku.supabase.co";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/** Shared secret used by pg_cron → Edge calls (mirrors private.get_cron_secret). */
function cronSecret(): string | null {
  return Deno.env.get("CRON_SECRET") ?? null;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

type Pref = {
  user_id: string;
  tenant_id: string | null;
  lat: number;
  lng: number;
  label: string | null;
  max_temp_c: number | null;
  min_temp_c: number | null;
  rain_probability_pct: number | null;
  max_wind_kph: number | null;
  window_start_hour: number | null;
  window_end_hour: number | null;
  quiet_start_hour: number;
  quiet_end_hour: number;
  local_hour: number;
  local_date: string;
  last_alert_on: string | null;
};

type Forecast = {
  maxC: number | null;
  minC: number | null;
  rainPct: number | null;
  windKph: number | null;
};

/** True when `hour` falls inside the quiet window, handling the wrap case. */
function inQuietHours(hour: number, start: number, end: number): boolean {
  if (start <= end) return hour >= start && hour < end;
  // Window wraps past midnight, e.g. 22 -> 06.
  return hour >= start || hour < end;
}

/** True when `hour` falls inside the user's chosen service window. */
function inWindow(
  hour: number,
  start: number | null,
  end: number | null,
): boolean {
  if (start === null || end === null) return true;
  if (start <= end) return hour >= start && hour <= end;
  return hour >= start || hour <= end;
}

async function fetchForecast(
  lat: number,
  lng: number,
  timezone: string,
): Promise<Forecast | null> {
  const url =
    "https://api.open-meteo.com/v1/forecast" +
    `?latitude=${lat}&longitude=${lng}` +
    "&daily=temperature_2m_max,temperature_2m_min," +
    "precipitation_probability_max,wind_speed_10m_max" +
    `&timezone=${encodeURIComponent(timezone)}&forecast_days=2`;

  // 8s: a slow forecast must not stall the whole sweep.
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 8000);
  try {
    const res = await fetch(url, { signal: ctl.signal });
    if (!res.ok) return null;
    const j = await res.json();
    const d = j?.daily;
    if (!d) return null;
    const n = (v: unknown): number | null =>
      typeof v === "number" && Number.isFinite(v) ? v : null;
    return {
      maxC: n(d.temperature_2m_max?.[0]),
      minC: n(d.temperature_2m_min?.[0]),
      rainPct: n(d.precipitation_probability_max?.[0]),
      windKph: n(d.wind_speed_10m_max?.[0]),
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Decide the single most urgent breached threshold, or null. */
function evaluate(
  p: Pref,
  f: Forecast,
): { kind: string; body: string } | null {
  const where = p.label ? ` near ${p.label}` : "";
  const r = (n: number | null) => (n === null ? "?" : String(Math.round(n)));

  if (p.max_temp_c !== null && f.maxC !== null && f.maxC >= p.max_temp_c) {
    return {
      kind: "heat",
      body: `Very hot today: ${r(f.maxC)}°C expected${where}. Stay hydrated.`,
    };
  }
  if (p.min_temp_c !== null && f.minC !== null && f.minC <= p.min_temp_c) {
    return {
      kind: "cold",
      body: `Cold today: ${r(f.minC)}°C expected${where}. Dress warmly.`,
    };
  }
  if (
    p.rain_probability_pct !== null &&
    f.rainPct !== null &&
    f.rainPct >= p.rain_probability_pct
  ) {
    return {
      kind: "rain",
      body:
        `Rain likely today: ${r(f.rainPct)}% chance${where}. ` +
        "Take an umbrella for the service.",
    };
  }
  if (p.max_wind_kph !== null && f.windKph !== null && f.windKph >= p.max_wind_kph) {
    return {
      kind: "wind",
      body: `Strong winds today: up to ${r(f.windKph)} km/h${where}. Secure outdoor items.`,
    };
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get("action") ?? "";

  // Secret-free health probe for ops.
  if (action === "health") {
    return new Response(
      JSON.stringify({
        status: "ok",
        cron_secret_set: !!cronSecret(),
        service_role_set: !!SERVICE_ROLE,
      }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  let actionName = action;
  if (!actionName) {
    try {
      const body = await req.json();
      actionName = String(body?.action ?? "sweep");
    } catch {
      actionName = "sweep";
    }
  }

  const dryRun = actionName === "preview";

  if (!dryRun) {
    // The sweep is privileged: it reads every opted-in user and sends push.
    const provided = req.headers.get("x-cron-secret") ?? "";
    const expected = cronSecret();
    if (!expected || provided !== expected) {
      return new Response(
        JSON.stringify({ error: "unauthorized" }),
        { status: 401, headers: { ...cors, "Content-Type": "application/json" } },
      );
    }
  }

  if (!SERVICE_ROLE) {
    return new Response(
      JSON.stringify({ error: "service_role_missing" }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false },
  });

  // The DB resolves the location (user's own, else their church), the local
  // hour/date, and the once-per-day dedupe in a single pass.
  const { data: prefs, error } = await admin.rpc("weather_alert_candidates");
  if (error) {
    return new Response(
      JSON.stringify({ error: "candidates_failed", detail: error.message }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  const list = (prefs ?? []) as Pref[];

  // ONE forecast fetch per distinct coordinate, not per user. A congregation
  // sharing one venue therefore costs a single upstream request.
  const cache = new Map<string, Forecast | null>();
  let sent = 0;
  let skipped = 0;
  let fetchFailures = 0;
  const results: Array<Record<string, unknown>> = [];

  for (const p of list) {
    if (p.last_alert_on && p.last_alert_on === p.local_date) {
      skipped++;
      continue;
    }
    if (inQuietHours(p.local_hour, p.quiet_start_hour, p.quiet_end_hour)) {
      skipped++;
      continue;
    }
    if (!inWindow(p.local_hour, p.window_start_hour, p.window_end_hour)) {
      skipped++;
      continue;
    }

    const key = `${p.lat.toFixed(2)},${p.lng.toFixed(2)}`;
    let f = cache.get(key);
    if (f === undefined) {
      f = await fetchForecast(p.lat, p.lng, "auto");
      cache.set(key, f);
      if (f === null) fetchFailures++;
    }
    // A failed forecast must NOT consume the user's one daily alert.
    if (f === null) {
      skipped++;
      continue;
    }

    const hit = evaluate(p, f);
    if (!hit) {
      skipped++;
      continue;
    }

    results.push({ user: p.user_id, kind: hit.kind, body: hit.body });

    if (dryRun) continue;

    // Claim the day's slot FIRST (conditional), so two concurrent sweeps can
    // never both send.
    const { data: claimed } = await admin
      .from("weather_alert_preferences")
      .update({ last_alert_on: p.local_date, last_alert_kind: hit.kind })
      .eq("user_id", p.user_id)
      .neq("last_alert_on", p.local_date)
      .select("user_id");

    if (!claimed || claimed.length === 0) continue; // someone else won the race

    await admin.from("notifications").insert({
      user_id: p.user_id,
      title: "Weather update",
      body: hit.body,
      type: "weather",
      reference_id: hit.kind,
    });

    // Device push via the existing shared helper path.
    await admin.functions.invoke("push-notifications", {
      body: {
        userIds: [p.user_id],
        title: "Weather update",
        body: hit.body,
        skipInApp: true,
        data: { type: "weather", channel_id: "coa_announcements_v2" },
      },
    });

    sent++;
  }

  return new Response(
    JSON.stringify({
      ok: true,
      dry_run: dryRun,
      candidates: list.length,
      forecast_fetches: cache.size,
      forecast_failures: fetchFailures,
      skipped,
      sent,
      alerts: results.slice(0, 50),
    }),
    { headers: { ...cors, "Content-Type": "application/json" } },
  );
});
