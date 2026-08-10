# UI/UX & Performance Remediation Plan

This plan addresses the high-impact issues identified in the UI/UX audit report dated 2026-08-05. The primary focus is on accessibility (font sizes), theme integrity (dark mode fixes), and navigation consistency.

## User Review Required

> [!IMPORTANT]
> Some screens that were forced to "Dark" mode (like Security, Identity) will be reviewed for consistency. If the design choice was intentional for branding, we will maintain the aesthetic but ensure it uses theme-aware colors to avoid hardcoded black/white clashes.

## Proposed Changes

### 1. Accessibility: Font Size Normalization (P0)

We will bump all font sizes below 11px to at least 11px (using `kMinUIFontSize` from `AppTheme`).

#### [MODIFY] [profile_screen.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/profile/presentation/profile_screen.dart)
#### [MODIFY] [main_navigation_shell.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/navigation/presentation/main_navigation_shell.dart)
#### [MODIFY] [home_screen.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/home/presentation/home_screen.dart)
#### [MODIFY] [membership_card_screen.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/profile/presentation/membership_card_screen.dart)
#### [MODIFY] [marketplace_screen.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/marketplace/presentation/marketplace_screen.dart)

### 2. Theme Integrity & Dark Mode Fixes (P1)

We will replace hardcoded `Colors.*` with semantic colors from `ColorScheme` and fix "white card" issues in dark mode.

#### [MODIFY] [app_theme.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/core/theme/app_theme.dart)
- Add `StatusColor` utility.
- Ensure all component themes (dialog, bottomSheet, etc.) use `surface` and `onSurface` correctly.

#### [MODIFY] [login_screen.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/auth/presentation/login_screen.dart)
- Fix white input containers in dark mode.

#### [MODIFY] [support_hub_screen.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/support/presentation/support_hub_screen.dart)
- Fix unthemed white cards and black chips.

### 3. Navigation: GoRouter Migration (P2)

We will migrate `Navigator.push` calls to `context.push` for better guard enforcement and deep linking.

#### [MODIFY] [home_quick_actions.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/features/home/presentation/widgets/home_quick_actions.dart)
#### [MODIFY] [app_router.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/core/routes/app_router.dart)

### 4. Error UX & Shared Widgets (P2)

#### [NEW] [app_error_view.dart](file:///D:/Explorer/MAYUNDO/KEY PROJECTS/churchonapp_flutter/lib/core/widgets/app_error_view.dart)
#### [MODIFY] Multiple Screens
- Replace raw `"Error: $e"` with `AppErrorView`.

## Verification Plan

### Manual Verification
- **Dark Mode Check**: Open Login and Support Hub in dark mode to verify no white glare blocks.
- **Accessibility Check**: Verify that "ON DUTY" labels in Profile and Bottom Nav labels are legible.
- **Navigation Check**: Verify that tapping "Quiz" in Quick Actions correctly triggers the subscription guard in `app_router.dart`.
