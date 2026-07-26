# Church On App - Supabase Deployment Script
# Run from project root: .\supabase\deploy.ps1

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Church On App - Supabase Deployment"   -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ─── Step 1: Apply Migrations ──────────────────────────────────────────
Write-Host "[1/5] Applying migrations..." -ForegroundColor Yellow

# Order matters: run in sequence
$migrations = @(
    "20260722_emergency_contacts.sql"
    "20260723_fix_recursive_rls_and_add_missing.sql"
    "20260724000001_comprehensive_fixes.sql"
    "20260724000001_fix_messages_rls_and_channel_id.sql"
    "20260724000002_fix_recursive_profiles_rls.sql"
    "20260725000001_fix_community_tenant_filtering.sql"
    "20260725000002_quiz_seasons_and_leases.sql"
    "20260725000003_fix_group_contrib_rpcs_and_errors.sql"
    "20260725_atomic_coins_and_tenant_scoping.sql"
    "2026072501_coa_direct_payments.sql"
    "20260726_pvp_elo_and_matches.sql"
    "2026072601_year_planner_plus.sql"
    "20260727_infinite_questions_and_tournaments.sql"
    "2026072700_performance_consistency_fixes.sql"
    "20260728_final_polish_phase1.sql"
    "20260728_sync_coins_and_balance_cc.sql"
    "20260728_verification_system.sql"
    "20260729_church_insert_rls_fix.sql"
    "20260729_comprehensive_db_fixes.sql"
    "20260729_fix_all_42p17_security_definer.sql"
    "20260729_fix_id_sequences_rls.sql"
    "20260729_fix_remaining_42p17.sql"
    "20260729_fix_tenants_rls_policy.sql"
    "20260729_klip_likes_recommendations.sql"
    "20260729_messaging_social_marketplace_fix.sql"
    "20260729_seed_radio_stations.sql"
    "20260729_whatsapp_fields_jobs_events_fix.sql"
    "20260730_deploy_final_changes.sql"
    "20260730_fix_chat_rls_and_realtime.sql"
    "20260730_saved_klips_and_comments.sql"
    "20260731_service_reports_table.sql"
    "20260731234567_fix_user_notes_reference.sql"
    "20260802_pledges.sql"
    "20260803_tenant_momo_payout.sql"
    "20260804_add_profiles_insert_policy.sql"
    "20260805_add_payout_approvers.sql"
    "20260806_quiz_enhancements.sql"
    "20260807000000_add_birthday.sql"
    "20260807000001_add_klip_duration.sql"
    "20260807000002_add_service_ratings.sql"
    "20260807000003_fix_profiles_rls_definitive.sql"
    "20260807000004_rename_speed_demon.sql"
    "20260812_marketplace_reviews.sql"
    "20260813_quiz_rls_and_pvp_fix.sql"
    "20260814000000_fix_profiles_rls_definitive_real.sql"
    "20260815000000_notification_preferences.sql"
    "20260816_rls_security_audit_fixes.sql"
    "20260818_game_settings_and_bookshop_stock.sql"
    "20260820_discipleship_and_kids_complete.sql"
    "20260820_seed_emergency_contacts.sql"
    "20260821_bus_routes_and_traffic.sql"
    "20260825_final_enhancements.sql"
    "20260826_add_churchid_tenantid.sql"
    "20260826_final_deploy.sql"
    "20260826_final_fixes.sql"
    "20260826_tenants_table.sql"
    "20260827_bookshops_and_users.sql"
    "20260827_reassign_users_to_rock_of_ages.sql"
    "20260828_expansion_bookshops_pvp.sql"
    "20260828_seed_churches_only.sql"
    "20260829_country_prefix_ids_migration.sql"
    "20260830_coa_code_generator_registry.sql"
    "20260831_security_events_whatsapp_email.sql"
    "20260832_linter_warnings_fix.sql"
)

foreach ($m in $migrations) {
    $path = "supabase\migrations\$m"
    if (Test-Path $path) {
        Write-Host "  $m..." -ForegroundColor Gray
        $result = supabase db query --linked --file $path 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    OK" -ForegroundColor Green
        } else {
            Write-Host "    $result" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  $m [NOT FOUND]" -ForegroundColor Red
    }
}

Write-Host "  Done." -ForegroundColor Green

# ─── Step 2: Deploy Edge Functions ─────────────────────────────────────
Write-Host ""
Write-Host "[2/5] Deploying Edge Functions..." -ForegroundColor Yellow

$functions = @(
    "push-notifications"
    "bible-study-notify"
    "send-sms"
    "lipila-collect"
    "lipila-webhook"
    "lipila-settle"
    "lipila-payout"
    "r2-sign"
    "cloudflare-stream"
    "send-birthday-email"
    "export-church-data"
    "export-user-data"
    "delete-account"
    "database-backup"
    "migrate-to-r2"
    "migrate-coa-payments"
    "kael-ai"
    "turn-credentials"
    "well-known"
    "generate-quiz-batch"
)

foreach ($f in $functions) {
    $path = "supabase\functions\$f"
    if (Test-Path $path) {
        Write-Host "  Deploying $f..." -ForegroundColor Gray
        supabase functions deploy $f --no-verify-jwt 2>&1
    } else {
        Write-Host "  $f [NOT FOUND]" -ForegroundColor Red
    }
}

Write-Host "  Done." -ForegroundColor Green

# ─── Step 3: Verify Auth & Function Configuration ──────────────────────
Write-Host ""
Write-Host "[3/5] Verifying secrets configuration..." -ForegroundColor Yellow
Write-Host "  Ensure these Edge Function secrets are set:" -ForegroundColor Gray
Write-Host "    - FCM_PROJECT_ID" -ForegroundColor Gray
Write-Host "    - FCM_SERVICE_ACCOUNT" -ForegroundColor Gray
Write-Host "    - FCM_SERVER_KEY" -ForegroundColor Gray
Write-Host "    - LIPILA_API_KEY" -ForegroundColor Gray
Write-Host "    - LIPILA_WEBHOOK_SECRET (for webhook signature verification)" -ForegroundColor Gray
Write-Host "    - LIPILA_PAYOUT_WEBHOOK_URL (webhook for payout confirmations)" -ForegroundColor Gray
Write-Host "    - CLOUDFLARE_R2_ACCESS_KEY_ID" -ForegroundColor Gray
Write-Host "    - CLOUDFLARE_R2_SECRET_ACCESS_KEY" -ForegroundColor Gray
Write-Host "    - SMS_API_KEY" -ForegroundColor Gray
Write-Host "  Use: supabase secrets set KEY=value" -ForegroundColor Gray
Write-Host "  Done." -ForegroundColor Green

# ─── Step 4: Build Flutter App ─────────────────────────────────────────
Write-Host ""
Write-Host "[4/5] Running Flutter analysis..." -ForegroundColor Yellow
flutter analyze --no-fatal-infos --no-fatal-warnings
if ($LASTEXITCODE -ne 0) {
    Write-Host "  WARNING: Flutter analysis found issues." -ForegroundColor Yellow
} else {
    Write-Host "  All clear!" -ForegroundColor Green
}

# ─── Step 5: Summary ──────────────────────────────────────────────────
Write-Host ""
Write-Host "[5/5] Deployment Summary" -ForegroundColor Yellow
Write-Host "  Migrations: $($migrations.Count) files" -ForegroundColor Gray
Write-Host "  Edge Functions: $($functions.Count) functions" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Deployment complete!"                   -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
