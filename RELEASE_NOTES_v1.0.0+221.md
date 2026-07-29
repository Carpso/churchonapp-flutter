# Release Notes — v1.0.0+221

## What's New

### 🔐 Security & Audit Fixes
- **Lipila webhook auth**: HMAC signature now always enforced (Bearer token bypass removed)
- **Subscription paywall**: ALL users blocked when church trial expires (previously only admins were blocked — F1 fix)
- **Cross-tenant RLS leaks**: Fixed SELECT policies on social_posts, sermons, events, live_chat_messages, marketplace_items — now scoped by tenant_id
- **Quiz feature gating**: Subscription check added to quiz routes and BibleQuizHubScreen
- **Quiz answer shuffling**: Options now randomly shuffled each game to prevent cheating

### 🛡️ Null Safety
- 17 unguarded `auth.currentUser!` calls fixed with null guards
- 12+ unguarded map lookups on dialog results fixed
- `Permission.camera` null bang fixed

### 🧭 Navigation Redesign
- **Bottom nav tabs permanently**: Home, Sermons, Give, Connect, Profile (Carpso Ride removed from tab bar)
- **Auto-hide on scroll**: Bottom nav hides when scrolling down, reappears when scrolling up — applied to ALL tabs via shell-level listener
- **Carpso Ride now dynamic**: Appears contextually where rides/delivery make sense:
  - Home screen — "Need a ride to church?"
  - Connect screen — "Carpool with church members"
  - Event details — "Ride to this event"
  - Marketplace — "Delivery available"
  - Also accessible via `/ride` route and `/ride` direct navigation

### 💬 Chat System Fixed
- **Send button now works**: `_isTyping` was never set to `true` — `TextEditingController` had no listener, keeping the send button permanently disabled showing a microphone icon. Added controller listener + always show send icon.

### 🚪 Logout Dialog Fixed
- Cancel button used wrong context (`Navigator.pop(context)` instead of `Navigator.of(ctx).pop()`), causing app to black out on cancel. Fixed with proper dialog-scoped context + `barrierDismissible: false`.

### 📨 Invite Link System
- Church onboarding generates `COA-ZM_CH_XXXX` invite codes
- Share button in success dialog with deep link
- Join Church screen handles `?code=` query param
- "Enter Invite Code" tile on church selection screen

### 📺 Streaming Trial
- Changed from 10 minutes/week to **10 minutes total lifetime** for trial churches
- Migration `20260844` — RPCs now SUM across all weeks, paid churches remain unlimited

### 📰 News Ticker Fixed
- Removed duplicate ticker on home screen (`NewsTicker` was rendering alongside `AnnouncementTicker` with the same content)

## Files Changed
- 30+ files across lib/ and supabase/
- Migration: `20260843_rls_tenant_scoping.sql`, `20260844_streaming_trial_total.sql`
- APK v1.0.0+221 built
