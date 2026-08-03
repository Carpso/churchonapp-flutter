export async function checkRateLimit(
  supabase: ReturnType<typeof import("https://esm.sh/@supabase/supabase-js@2").createClient>,
  adminId: string,
  actionType: string,
  maxRequests = 30,
  windowMinutes = 1
): Promise<{ allowed: boolean; remaining: number }> {
  try {
    const { data, error } = await supabase.rpc("check_admin_rate_limit", {
      p_admin_id: adminId,
      p_action_type: actionType,
      p_max_requests: maxRequests,
      p_window_minutes: windowMinutes,
    });

    if (error) {
      console.error("Rate limit check failed:", error);
      return { allowed: false, remaining: 0 };
    }

    return { allowed: data as boolean, remaining: maxRequests - 1 };
  } catch {
    return { allowed: false, remaining: 0 };
  }
}
