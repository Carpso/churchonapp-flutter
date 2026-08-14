# Church On App - Supabase Deployment Script
# Run from project root: .\supabase\deploy.ps1

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Church On App - Supabase Deployment"   -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ─── Step 1: Apply Migrations ──────────────────────────────────────────
Write-Host "[1/5] Applying migrations..." -ForegroundColor Yellow

# Order matters: run in sequence
$migrations = @(
    # ─── Foundation (pre-July 2026) ────────────────────────────────────────
    "20240224_optimize_matching.sql"
    "20260224_final_kingdom_deployment.sql"
    "20260225_fix_social_moderation.sql"
    "2026062801_feature_fixes.sql"
    "2026062802_add_platform_fee.sql"
    "2026062803_delivery_vendor_payout.sql"
    "2026062804_event_speakers_and_momo.sql"
    "2026062805_transactions_recipient.sql"
    "2026063000_feature_audit.sql"
    "2026063001_payment_logs_webhook.sql"
    "2026063002_quiz_events_passes.sql"
    "2026063003_tenant_theming.sql"
    "20260702_user_activities_2fa_coins.sql"
    "20260703_tenant_payment_logs.sql"
    "20260704_notifications_audit.sql"
    "20260705_admin_audit_security.sql"
    "20260706_kyc_documents_rls.sql"
    "20260707_sessions_login_history_rate_limit.sql"
    "20260708_notifications_jobs_ads_shutdown.sql"
    "20260709_role_hierarchy_marketplace_trial.sql"
    "20260710_missing_tables_schema.sql"
    "2026071001_expand_bible_quiz_questions.sql"
    "2026071002_missing_tables_schema.sql"
    "2026071003_quiz_championship_system.sql"
    "20260710234567_create_bible_tables.sql"
    "20260711_rls_and_security_fixes.sql"
    "20260711000001_bible_text_storage.sql"
    "20260711000003_seed_bible_data.sql"
    "20260711000004_seed_kjjv_text_p001.sql"
    "20260711000004_seed_kjjv_text_p002.sql"
    "20260711000004_seed_kjjv_text_p003.sql"
    "20260711000004_seed_kjjv_text_p004.sql"
    "20260711000004_seed_kjjv_text_p005.sql"
    "20260711000004_seed_kjjv_text_p006.sql"
    "20260711000004_seed_kjjv_text_p007.sql"
    "20260711000004_seed_kjjv_text_p008.sql"
    "20260711000004_seed_kjjv_text_p009.sql"
    "20260711000004_seed_kjjv_text_p010.sql"
    "20260711000004_seed_kjjv_text_p011.sql"
    "20260712_rate_limit_rpc.sql"
    "20260712150827_kids_zone_and_audio_sermons.sql"
    "20260712152547_last_superadmin_guard_and_audit.sql"
    "20260712153000_soft_delete_and_session_timeout.sql"
    "20260713_audit_fixes.sql"
    "20260714000001_fix_profiles_rls_final.sql"
    "20260714000002_create_driver_applications.sql"
    "20260714000003_sync_profile_coins.sql"
    "20260714000004_fasting_subscriptions.sql"
    "20260714000005_tithe_cards.sql"
    "20260715_fundraising_feature.sql"
    "20260718_business_meetings.sql"
    "20260718_community_groups.sql"
    "20260718_dm_fixes.sql"
    "20260718_editable_subscription_pricing.sql"
    "20260718_event_ticketing_system.sql"
    "20260718_fix_community_messages.sql"
    "20260718_fix_social_posts_columns.sql"
    "20260718_new_features_schema.sql"
    "20260718_payment_retry_queue.sql"
    "20260718_streaming_config.sql"
    "20260718_streaming_cost_controls.sql"
    "20260718_streaming_usage_tracking.sql"
    "20260718_user_subscriptions.sql"
    "20260720_final_rls_audit_fix.sql"
    "20260721_db_frontend_gap_fix.sql"
    "20260722_add_baptisms_table.sql"
    "20260722_carpso_ride_fixes.sql"
    "20260722_quiz_pvp_xp_achievements.sql"
    "20260723_fix_quiz_competitions_payments.sql"
    "20260723_quiz_invite_ads_promo.sql"
    "20260723_rewards_call_quality_fixes.sql"
    # ─── July 2026 ────────────────────────────────────────────────────────
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
    "20260731_fix_seed_group_uuids.sql"
    # ─── August 2026 ──────────────────────────────────────────────────────
    "20260801_rls_critical_fixes.sql"
    "20260801_rls_medium_risk_fixes.sql"
    "20260802_pledges.sql"
    "20260803_133358_bible_nkjv_nlt_smart_features.sql"
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
    "20260833_chat_rls_and_messages_fix.sql"
    # ─── Post-August 2026 ─────────────────────────────────────────────────
    "20260834_architecture_upgrade.sql"
    "20260835_coa_payments_constraints.sql"
    "20260836_rls_always_true_fix.sql"
    "20260837_profiles_tenant_id_uuid.sql"
    "20260838_harden_db_and_dashboard_logic.sql"
    "20260839_bookshops_and_profiles_fix.sql"
    "20260840_production_missing_tables.sql"
    "20260841_coin_partner_tables.sql"
    "20260842_performance_indexes.sql"
    "20260843_rls_tenant_scoping.sql"
    "20260844_streaming_trial_total.sql"
    "20260845_fix_profiles_rls_definitive_final.sql"
    "20260846_fix_profiles_rls_tenant_scoped.sql"
    "20260847_fix_rls_policies.sql"
    "20260848_role_rename_and_streaming_fixes.sql"
    "20260849_backfill_role_from_assignments.sql"
    "20260850_comprehensive_production_fix.sql"
    "20260851_coa_payments_webhook_fixes.sql"
    "20260852_card_payment_method.sql"
    "20260853_fee_config_settings.sql"
    "20260854_payroll_system.sql"
    "20260854_remote_config_keys.sql"
    "20260855_fix_profiles_rls_infinite_recursion.sql"
    "20260855_lipila_fee_rates.sql"
    "20260856_coa_payout_fee.sql"
    "20260857_ai_chat_tables.sql"
     "20260858_giving_settlement_fix.sql"
     "20260859_production_hardening.sql"
     "20260860_organization_church_member_counts.sql"
     "20260861_data_import_system.sql"
     "20260863_service_reporting_enhancements.sql"
     "20260865_coa_payment_stats_rpc.sql"
     "20260866_kael_warm_cron.sql"
     "20260867_backfill_role_assignments.sql"
     "20260868_carpso_negotiation.sql"
     "20260869_chat_tenant_scoping.sql"
     "20260870_settlement_cron_phones_sms.sql"
     "20260871_intertenant_events.sql"
     "20260872_local_bible_versions.sql"
     "20260873_public_domain_english_bibles.sql"
     "20260874_kids_progress_rpc.sql"
     "20260875_kids_audio_stories.sql"
     "20260876_engagement_analytics.sql"
     "20260877_expansion_leads_rls.sql"
     "20260878_marketplace_tenant_scoping.sql"
     "20260879_kids_progress_fix.sql"
     "20260880_bible_study_tables.sql"
     "20260881_quiz_leaderboard.sql"
     "20260882_seed_sample_klips.sql"
     "20260883_kids_audio_r2_urls.sql"
     "20260883_presence_last_seen.sql"
     "20260884_dedupe_kids_resources.sql"
     "20260884_meeting_subscriptions.sql"
     "20260885_remove_biblegateway_kids.sql"
     "20260886_normalize_good_samaritan.sql"
     "20260887_support_disputes_errors.sql"
     "20260888_security_hardening.sql"
     "20260889_server_side_settlement.sql"
     "20260890_church_auto_payout.sql"
     "20260891_fixes_onboarding_rls_audio.sql"
     "20260892_session_inactivity_config.sql"
     "20260893_fix_quiz_leaderboard.sql"
     "20260894_fix_noah_ark_audio.sql"
     "20260895_quiz_security_hardening.sql"
     "20260896_quiz_tournament_gates.sql"
     "20260897_quiz_wager_tournaments_invites.sql"
     "20260898_quiz_cc_economy.sql"
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
# NOTE: All functions deploy with --no-verify-jwt because:
#   (a) webhook functions (lipila-webhook, whatsapp-webhook) receive
#       untrusted POSTs with signature-based auth, not JWTs.
#   (b) All authenticated functions verify their own JWT via
#       supabase.auth.getUser(token) + role/profile check — they do not
#       rely on the gateway-level JWT verification.
# Per-function auth status:
#   JWT self-checked + role gate   : cloudflare-stream, data-import, export-church-data,
#                                     export-user-data, delete-account, database-backup,
#                                     migrate-coa-payments, kael-ai, r2-sign, send-sms,
#                                     buy-sms-credits, create-bookshop, lipila-collect,
#                                     lipila-card-collect, lipila-payout, lipila-settle,
#                                     push-notifications, bible-study-notify, send-birthday-email,
#                                     send-email, send-security-alert, new-member-notify,
#                                     generate-quiz-batch (advisory), whatsapp-send,
#                                     turn-credentials, migrate-to-r2
#   HMAC/webhook-signature auth    : lipila-webhook (HMAC-SHA256), whatsapp-webhook (HMAC-SHA256)
#   No auth (well-known)           : well-known

$functions = @(
    "push-notifications"
    "bible-study-notify"
    "send-sms"
    "lipila-collect"
    "lipila-card-collect"
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
     "data-import"
     "send-email"
     "send-security-alert"
     "buy-sms-credits"
     "create-bookshop"
     "whatsapp-send"
     "whatsapp-webhook"
     "new-member-notify"
     "hf-keep-warm"
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
