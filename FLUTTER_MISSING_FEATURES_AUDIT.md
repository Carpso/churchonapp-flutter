# ChurchOnApp Flutter Migration - Audit & Missing Features Report

This report summarizes the current state of the **Church On App Flutter migration** (`c:\churchonapp_flutter`) as of February 2026. This version is a migration from the React version, aimed at superior performance and UI consistency.

## 1. Functional State Summary
While the Flutter version has a premium and clean visual design, many core features are currently **UI Shells** with minimal functionality or hardcoded data.

### A. Missing Backend Integrations (Hardcoded UI)
- **Admin Hub Statistics:** The total member counts, growth rates, and giving stats in `AdminHubScreen` are hardcoded dummy values.
- **Wallet Transactions:** The recent transactions list in the `WalletScreen` is a hardcoded list of placeholders.
- **Member Management:** The "Member Management", "Financial Oversight", and "Media Hub" screens exist but are largely disconnected from live data logic.

### B. Inactive UI Elements (Empty Handlers)
- **Finance Module:**
    - "Top Up", "Send", and "Withdraw" buttons in `WalletScreen` have empty handlers.
- **Admin Module:**
    - "Global Broadcast" and "Event Scheduling" in the `AdminHubScreen` have empty handlers.
- **Kids Module:**
    - Activity cards in the `KidsZoneScreen` (Bible Trivia, Memory Verses, Coloring Book, Sunday School) do not have any defined click actions or navigation.

## 2. Feature Gaps vs. React Version
The following features from the original React super-app are either missing or in a "shell" state in Flutter:

1. **Kingdom Klips (Vertical Video):** While mentioned, the vertical video preloading and hardware-accelerated decoding logic from the migration plan needs verification/implementation.
2. **Flyer Studio:** The in-app graphic design tool for announcements is not yet ported.
3. **Zambian Compliance (Payroll):** NHIMA/NAPSA/PAYE statutory deductions logic present in the React admin panel is missing here.
4. **Bible Reader & Search:** Deep Study Suite features (reading plans, daily verses, highlighting) are still in early stages.
5. **Real-time Chat:** The Sovereign Matchmaking and real-time chat room logic needs to be fully bridged from Supabase.
6. **Fleet Management:** The "Logistics Oracle" for church buses and delivery riders is currently a shell without real-time map tracking.

## 3. High-Priority Migration Needs
To achieve parity with the React production version, development should focus on:
1.  **Bridging Supabase Providers:** Ensuring all Riverpod providers (like `profileProvider`) are correctly syncing with the existing Supabase backend.
2.  **Implementing Global Toast System:** Replicating the "Sunflower Toast" experience for error and status feedback.
3.  **Activating Action Buttons:** Connecting the "Top Up", "Give", and "Broadcast" buttons to their respective logic/screens.
4.  **Data Persistence:** Implementing local caching (using `Hive` as planned) for the Bible and Sermons library.
