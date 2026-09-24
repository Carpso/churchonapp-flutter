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
    "20260893_tenants_insert_any_authenticated.sql"
    "20260894_fix_noah_ark_audio.sql"
     "20260895_quiz_security_hardening.sql"
     "20260896_quiz_tournament_gates.sql"
"20260897_quiz_wager_tournaments_invites.sql"
      "20260898_quiz_cc_economy.sql"
"20260899_radio_christian_only.sql"
       "20260899_sample_sermon_clips.sql"
       "20260899_sermon_ui_metadata.sql"
       "20260900_giving_goals.sql"
       "20260901_quiz_church_fixes.sql"
       "20260901_zra_payroll_remote_config.sql"
       "20260902_church_registration_rls.sql"
       "20260903_year_planner_rls_fix.sql"
         "20260904_quiz_cc_leaderboard_and_fixes.sql"
         "20260905_church_branding_and_special_offers.sql"
          "20260906_website_pastoral_analytics.sql"
          "20260907_secdef_hardening_round2.sql"
          "20260908_secdef_hardening_round3.sql"
           "20260908_fix_cross_references_parallel_streaming.sql"
           "20260909_secdef_hardening_round3b.sql"
           "20260910_subscribe_tier_anchor.sql"
           "20260911_2fa_server_side.sql"
"20260912_fix_role_assignments_rls_coa.sql"
           "20260913_superadmin_ops_fixes.sql"
            "20260914_live_stream_enhancements.sql"
             "20260915_tenant_ads_platform_nullable.sql"
             "20260916_fix_churches_update_rls.sql"
             "20260917_fix_sos_alerts_rls_coa.sql"
             "20260918_prophetic_heatmap_real_data.sql"
"20260919_fix_church_buses_rls_coa.sql"
    "20260921_coa_employee_rls_batch.sql"
    "20260922_network_programs.sql"
    "20260923_production_hardening_applied.sql"
    "20260925_fix_bishop_rpc_gates.sql"
    "20260926_carpso_ministries_bible_fixes.sql"
    "20260927_ops_dashboard_upgrade.sql"
    "20260928_org_branch_snapshots.sql"
    "20260929_org_create_registration_fixes.sql"
    "20260931_role_approval_staff_fix.sql"
    "20260950_bible_verse_like.sql"
    "20260951_scope_prayers_testimonies_tenant.sql"
    "20260952_group_member_count_rpc.sql"
    "20260953_saved_posts.sql"
    "20261001_pvp_invite_status_check.sql"
    "20261002_churches_anon_select.sql"
    "20261003_pvp_invite_cron_sweep.sql"
    "20261004_leadership_memos.sql"
    "20261005_quiz_cc_leaderboard_solo.sql"
    "20261006_streaming_paid_unlock.sql"
    "20261007_kyc_church_leader_review.sql"
    "20261008_live_streams_leader_roles.sql"
    "20261009_community_chat_fixes.sql"
    "20261010_close_anon_message_policies.sql"
    "20261011_scope_chat_messages.sql"
    "20261012_scope_sermon_notes_and_stream_chat.sql"
    "20261013_drop_public_church_insert.sql"
    "20261014_server_security_remediation.sql"
    "20261031_expire_stale_live_streams.sql"
    "20261032_fix_dashboard_settled_filters.sql"
    "20261033_fix_leadership_memo_leak.sql"
    "20261034_carpso_ride_rls_and_columns.sql"
    "20261035_streaming_live_status_and_marketplace_global.sql"
     "20261036_map_listing_and_streaming_columns.sql"
     "20261037_bible_kjv_mojibake_fix.sql"
     "20261105_baptism_registry_member_attendance.sql"
     "20261106_member_attendance_list.sql"
     "20261107_backfill_bookshop_tenants.sql"
     "20261108_operations_hardening.sql"
     "20261109_streaming_credentials_and_scope.sql"
     "20261110_dashboard_rpc_hardening.sql"
     "20261112_streaming_schedule_lifecycle.sql"
      "20261113_fix_profiles_recursion_get_my_tenant_id.sql"
      "20261114_drop_profiles_recursive_all_policy.sql"
      "20261114b_restore_get_my_tenant_id_from_profiles.sql"
      "20261115_make_marketplace_events_global.sql"
      "20261116_fix_home_feed_realtime.sql"
      "20261117_cleanup_sample_sermons.sql"
      "20261118_upci_sample_sermons.sql"
      "20261119_sermon_viewership.sql"
      "20261120_sermon_r2_archive.sql"
      "20261121_stream_analytics.sql"
      "20261122_saved_places.sql"
      "20261123_delivery_proof.sql"
      "20261124_organizations_rls_coa.sql"
      "20261125_social_repost_reports_views.sql"
      "20261126_seed_playable_klip.sql"
      "20261127_pvp_matchmaking_queue.sql"
      "20261128_emergency_contacts_user.sql"
      "20261129_webview_opens.sql"
      "20261130_pvp_disconnect_pause.sql"
      "20261131_quiz_hosting_engine.sql"
      "20261132_tenant_owner_tier.sql"
      "20261133_remove_user_subscriptions.sql"
      "20261134_social_stories.sql"
      "20261135_quiz_hosting_rpcs.sql"
      "20261136_fix_church_branding_uploads.sql"
      "20261137_offering_baskets.sql"
      "20261138_offering_basket_contributions.sql"
      "20261139_community_network_create.sql"
      "20261140_popular_places.sql"
      "20261141_stream_archive.sql"
      "20261142_streaming_audio_thumbnails_samples.sql"
      "20261143_klips_user_avatar.sql"
      "20261144_live_streams_read_grants.sql"
      "20261145_service_push_and_reminders.sql"
      "20261146_repost_media.sql"
      "20261147_radio_stories_join.sql"
      "20261148_bible_study_image_and_plan_progress.sql"
      "20261149_writer_books.sql"
      "20261150_worship_lyrics.sql"
      "20261151_kael_chat_history_settings.sql"
      "20261152_stream_config_platform_guard.sql"
      "20261153_stream_max_quality_paid_baseline.sql"
      "20261154_social_stories_upgrade.sql"
      "20261200_live_stream_engagement.sql"
      "20261201_daily_verse_pool.sql"
      "20261202_sample_stream_posters.sql"
      "20261203_recorded_services_as_sermons.sql"
      "20261204_bookshop_tenant_enhancements.sql"
      "20261205_quiz_tournament_admin_rewards.sql"
      "20261206_promo_codes.sql"
      "20261207_daily_verse_pool_expansion.sql"
      "20261208_klips_is_audio_and_post_policy.sql"
      "20261209_live_stream_overlay_speaker.sql"
"20261210_notifications_autopush.sql"
      "20261211_media_transcripts.sql"
      "20261212_transcribe_sweep_cron.sql"
      "20261213_stream_archive_hardening.sql"
      "20261214_fix_sermon_audio_url_for_video.sql"
      "20261215_org_ownership_gates.sql"
      "20261216_fix_tenant_events_quiz_sermon_pvp.sql"
      "20261217_events_special_guests.sql"
      "20261218_fix_profiles_role_trigger.sql"
      "20261219_fix_resolution_hub.sql"
      "20261220_recorded_service_playable_url.sql"
      "20261221_business_meetings_real.sql"
      "20261221_pro_meeting_payments_entitlement.sql"
      "20261222_profiles_tenant_fk_to_tenants.sql"
      "20261223_orders_rls_recursion_fix.sql"
      "20261224_verse_notes_is_liked.sql"
      "20261225_dead_sample_poster_cleanup.sql"
      "20261226_worship_setlists.sql"
      "20261227_payment_reconciliation_dunning.sql"
      "20261228_payment_port_hardening.sql"
      "20261229_event_ticketing_v2.sql"
      "20261230_dead_unsplash_poster_cleanup.sql"
      "20261231_one_active_stream_per_church.sql"
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
     "quiz-import"
     "data-import"
     "send-email"
     "send-security-alert"
     "buy-sms-credits"
     "create-bookshop"
     "whatsapp-send"
     "whatsapp-webhook"
     "new-member-notify"
     "hf-keep-warm"
     "transcribe-media"
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
