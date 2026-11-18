# Shaire — UI/UX Audit & Polish

This document tracks the UI/UX issues found during the audit of the app and the fixes
applied. Grouped by severity: **bugs first**, then **polish**, then **snappiness**.

## Bugs / broken interactions (fixed)

1. **Home: pull-to-refresh was dead.** `RefreshIndicator` wrapped a non-scrollable
   `Column`, so the gesture could never trigger. → Home is now a `CustomScrollView`
   (slivers) and pull-to-refresh works from anywhere on the screen.
2. **Home: loading flash on every revisit.** `_fetchData()` set `_isLoading = true`
   unconditionally, so navigating back from Add Expense blanked the whole screen to a
   spinner. → Spinner only on the first load; revisits refresh silently over the
   existing content.
3. **Groups screen: jank on tab swipes.** `TabController.addListener(_tabChanged)`
   called `setState(() {})` on *every animation frame* while dragging, rebuilding the
   entire friends list at 60 fps. → Only rebuilds when the index actually changes.
4. **Expenses screen: dead buttons.** "See All" and "See More" had empty/TODO `onPressed`
   — tappable widgets that do nothing. → Removed (the honest fix is to not advertise them).
5. **Main shell: invisible-but-tappable app bar button.** On the Expenses tab the action
   button was built with `Icon(null)` hidden via a transparent foreground color — still
   focusable for TalkBack/VoiceOver. → Actions are now conditional per tab.
6. **Back button showed an "Exit App?" dialog and `exit(0)`.** Hard-killing the process
   skips lifecycle/draft-saving and annoys users. → Standard Android back behavior
   (app backgrounded); dialog and `exit(0)` removed.
7. **Splash screen waited a fixed 1500 ms** before even checking the session.
   → Auth check starts immediately; splash shows a 350 ms minimum so the brand frame
   still reads. Feels noticeably snappier on cold start.
8. **Profile: pull-to-refresh finished instantly.** `_refreshProfile` never awaited the
   future it handed to `FutureBuilder`, so the spinner vanished before data arrived.
   → Now awaits, and errors surface with a retry.
9. **Groups: `_joinGroupController.dispose()` called twice**; also fixed the unused
   duplicate disposal.
10. **Profile screen: dead code** — top-level `fetchUserProfile` / `updateUserProfile`
    duplicating `UserProvider` (and misusing the Supabase response object). Removed.

## Visual / accessibility (fixed)

11. **Contrast: white on brand green failed WCAG badly** (`onPrimary: Colors.white` on
    `#99CF70` ≈ 1.9:1). Affected every elevated button, the FAB, and the green
    "Friends & Groups" app bar. → `onPrimary` is now a deep ink green in the light
    theme (≈ 9:1); dark theme keeps its existing dark ink.
12. **FAB icon hardcoded `Colors.white`** in the shell, overriding theme foreground.
    → Theme-driven now.
13. **Hardcoded `Colors.green`/`Colors.red`** for balances, trends and friend net
    balance (washed out on dark backgrounds). → New `AppSemanticColors.positive/negative`
    helpers with tuned light/dark values.
14. **No `scrolledUnderElevation: 0`** → a grey tint bar appeared over content on
    scroll under transparent app bars. Fixed in `AppBarTheme`.
15. **Bottom tab bar was a hack** (raw `IconButton`s, 40 px targets, no selection
    indicator, labels 10 px with no animation). → Proper tappable widgets: 48 dp
    targets, animated pill indicator behind the selected icon, haptic tick on select,
    semantic labels.
16. **SnackBars were pinned at the very bottom**, covering the nav bar / content. →
    Floating, rounded, with margins via `SnackBarThemeData`.
17. **Dialogs, bottom sheets, chips, tab bar** had no theme — inconsistent radii and
    M3 surface tint. → `DialogThemeData` (r=24), `BottomSheetThemeData` (r=24 top),
    `TabBarThemeData` (no divider), outlined-button/dialog defaults unified.
18. **Theme switch now supports system**: first launch follows the platform brightness;
    the Settings toggle overrides and persists it.

## UX ergonomics (fixed)

19. **Auth screen**: no validation on fields (errors were snackbars after submit), no
    password visibility toggle, no autofill, no keyboard "next/done" actions, and the
    submit button swapped to a lone `CircularProgressIndicator` causing a layout jump.
    → `Form` with inline `TextFormField` validators, autofill hints, `TextInputAction`,
    visibility toggle on password fields, and in-button loading (no jump).
20. **Landing**: tagline used `FontWeight.w200` — illegible at small sizes on some
    devices. → `w400`.
21. **Groups screen search**: no way to clear; no empty-result action. → Clear button
    when text present; empty states now have an icon and a direct CTA
    ("Add friend" / "Create group") instead of telling users to hunt for the + button.
22. **Remove-from-recent-activity flow**: removing one row required a modal confirm
    dialog *twice over* (dismiss gesture also confirmed). → Swipe or tap removes
    instantly with an **Undo** snackbar — faster and still recoverable.
23. **Profile**: dark-mode toggle and currency were buried behind a settings icon that
    only appears on the Profile tab. → A "Preferences" card with inline dark-mode
    switch and currency selector sits on the profile screen itself.
24. **Responsive**: the phone layout stretched edge-to-edge on tablet/web/desktop.
    → Shell is adaptive: `NavigationRail` (labels always visible) with centered,
    width-capped content at ≥ 720 dp; the bottom bar + notched FAB on phones.
25. **Returning from Add Expense** refreshed only the Expenses tab's list.
    → Both expenses and overall balances are re-pulled, so Home is accurate too.

## Not changed (deliberate)

- Brand color `#99CF70` kept — only the ink on it changed.
- The AI/prediction pipeline, providers, and Supabase schema were left untouched.
- `AddExpenseScreen`'s auto-save/draft system is solid; only the save-button feedback
  was touched.

## Verification

- `flutter analyze` — no new issues (baseline was clean except Flutter-3.50 SDK
  deprecation infos unrelated to this repo).
- `flutter test` — existing widget tests pass.

---

# Round 2 — functional fixes (post-review)

## Gradients
- Removed the splash-screen gradient and the Home "Total Balance" card
  gradient. The balance card is now a flat surface card with an outline and
  a tinted sub-panel for You Get / You Owe — same hierarchy, no gradient.

## Friends screen
- **Removed the duplicate "Quick Expense" button.** `FriendDetailsScreen`
  had *both* an in-card "Quick Expense" button and a floating "Quick
  Expense" action button opening the exact same modal. The FAB is gone; the
  button in the balance card remains.

## Settle Up (was: fake success / silent no-op)
- Root cause found: `PaymentService.createPaymentRecord` caught every DB
  error, logged it, returned `false` — and the caller *ignored the return
  value*, so "Settlement recorded" was shown even when nothing was written.
  The service now throws on failure and `_settleUp` only claims success on
  a real insert; failures show "Could not record the payment…".
- `BalanceService.adjustBalance` could **invert a debt**: settling up with no
  pre-existing `balances` row inserted a negative row (fabricating an owed
  direction). Negative adjustments with no existing row are now skipped.
- **Custom (unlinked) friends now get a visible history entry** —
  `CustomFriendBalanceService.recordSettlement` writes a settlement row into
  the activity list (rendered with a handshake icon, not tappable) instead of
  silently nudging a local number.
- **Settle-up dialog rebuilt**: direction is explicit and switchable
  (SegmentedButton: "You pay X" / "X pays you", defaulting to whoever owes),
  amount is editable with a "Full" shortcut, optional note, validation.
  Old dialog had a checkbox to *disable* entering a custom amount and a
  hardcoded ₹ prefix regardless of the user's currency; currency symbol now
  comes from `CurrencyProvider`.
- After settling, the friends list balances refresh in both code paths.

## Notifications (was: dead "coming soon" bell)
- `NotificationService` had CRUD-by-id but **no way to list a user's
  notifications**, even though `QuickExpenseService` writes rows into
  `notifications` on every quick expense.
- Added `fetchRecentForUser`, `unreadCountForUser`, `markAllReadForUser`.
- New `NotificationsSheet` (drag-to-resize bottom sheet): type icons, bold
  for unread with a dot marker, relative timestamps, pull-to-refresh,
  empty + error/retry states.
- The home bell now opens it and shows an unread `Badge` count, refreshed
  when the sheet closes.

## Reliability misc
- Expenses screen: the "Failed to load predictions" card is a dead end with
  no recovery; it now has a "Try again" button that force-refetches.
- Friends list rows (Groups tab): the long-press quick-action modal's
  success snackbar colors follow `AppSemanticColors` now (dark-safe).

## Verification (round 2)
- `flutter analyze`: no new issues (same 36 pre-existing Flutter-3.50
  SDK-deprecation infos).
- `flutter test`: 15/15 pass.

---

# Round 3 — caching & refresh strategy (plus workspace slim-down)

## Problem
Every screen re-hit Supabase on each visit: Home fetched expenses + balances
on load *and* on every `didPopNext`; Expenses refetched on every return; the
Groups tab refetched friends + groups on every open. Tab switching paid full
network latency, and concurrent opens (Home + Expenses in an `IndexedStack`)
double-fetched the same endpoints.

## Fix: memory cache + forced invalidation + Supabase Realtime
- **`lib/services/data_cache.dart` (new)** — per-key TTL cache with:
  - 30–45 s freshness window → tab switches render instantly from memory;
  - **coalescing** — concurrent fetches of the same key share one request;
  - `force: true` for pull-to-refresh and post-mutation refreshes;
  - failed fetches never mark a key fresh; `reset()` clears everything.
- **`lib/services/realtime_service.dart` (new)** — one shared
  `postgres_changes` channel watching `expenses, expense_participants,
  payments, balances, groups, group_members, friendships, custom_friends,
  notifications, profiles`. Bursts are debounced (600 ms) and every provider
  listening to those tables refetches with `force: true` — so **updates from
  other devices land within ~1 s** without polling. If a table isn't in the
  DB's `supabase_realtime` publication, nothing breaks: the TTL still
  guarantees eventual refresh.
- **Providers** (`ExpenseProvider`, `GroupProvider`, `FriendProvider`):
  all list fetches (`fetchExpenses`, `fetchUserOverallBalances`,
  `fetchGroups`, `fetchFriendsAndRequests`, per-group `fetchGroupExpenses`)
  gained `force` and are cache-wrapped; **every local mutation path now forces
  a refresh** (create/update/delete expense, group create/join/rename, friend
  request responses…) so cache never hides your own write; the group-expense
  memoization is keyed per group id and cleared on realtime events.
- **Screens**: `didPopNext` reloads stay *unforced* (cheap, cache-aware);
  `RefreshIndicator` passes `force: true`; FriendDetails' provider-listener
  reload is throttled to 4 s to avoid RPC storms during refresh bursts.
- **Sign out** resets `DataCache` and unsubscribes the realtime channel, so a
  different account never sees the previous one's cached rows.
- Correctness bug found along the way: `fetchExpenses` only queried
  `created_by = me` — **expenses a friend created and split with you were
  missing from the Expenses tab and Home**. The query now unions
  `expense_participants` rows (with a safe fallback to the old query).

## Tests
New `test/data_cache_test.dart` (8 tests): freshness, force bypass,
concurrent coalescing, invalidate, failure-doesn't-mark-fresh, key
independence, and custom-friend `recordSettlement` balance + history.

## Note for the Supabase project
To make cross-device updates instant, add the watched tables to the
`supabase_realtime` publication (Dashboard → Database → Replication). Until
then the TTL keeps data at most ~30 s stale after remote changes — every
in-app mutation is already immediate.

---

# Round 4 — settle-up insert fix + brand-consistent success/error colors

## 1. `null value in column "payment_id" violates not-null constraint`
**Cause.** `PaymentService.createPaymentRecord` inserted into `payments`
without `payment_id`. That column is `NOT NULL` and has **no database
default** (the model documents it as a client-generated business id:
`Payment.paymentId`). Upstream's original payment writer swallowed every
error, so the shape of this insert had never actually succeeded; once
settle-up started reporting failures (round 2), the 23502 surfaced to the
user.

**Fix.** `lib/database/payment.dart`:
- row construction extracted into `PaymentService.buildSettlementRow(...)`,
  which always sends `payment_id: const Uuid().v4()` alongside
  `from_user_id / to_user_id / amount / currency / payment_method /
  payment_date / status / notes` (the `uuid` package was already a
  dependency);
- `createPaymentRecord` now just inserts that row;
- `test/settlement_payment_test.dart` (4 tests) pins the column set, the
  UUIDv4 shape, per-row uniqueness and the fields the history list and
  balance math read — so the payload cannot regress silently again.

**Optional hardening on the database** (makes every writer safe, including
the legacy `PaymentService.createPayment` DAO, which is not called from the
UI today):

```sql
alter table only public.payments
  alter column payment_id set default gen_random_uuid();
```

Skip it if `payment_id` is instead a foreign key to another table — then
tell me and the row builder will send that id instead of a fresh UUID.

## 2. Palette: one green, one softer red
Success and error used Material's `Colors.green` / `Colors.red` in ~35
places, unrelated to the brand; the semantic tokens were a forest green and
a fairly saturated red.

- `AppSemanticColors.positive` is now the **brand green**: dark mode is the
  literal `AppTheme.primaryColor` (`#99CF70`), light mode is the same hue and
  saturation inked to `#477326` (5.6:1 on white) because `#99CF70` text on a
  white card is unreadable (~1.9:1). Change one constant in
  `lib/theme/theme.dart` if you want the exact primary as text regardless.
- New surface tokens: `positiveFill` = the app primary green (used by every
  success snackbar, with dark brand ink `onPositiveFill` on top) and
  `negativeFill` = a desaturated `#A65B53` for error snackbars and destructive
  buttons (white text still clears 4.5:1).
- `AppSemanticColors.negative` (balances, "you owe" text) is washed out to
  `#B0554D` light / `#E39A92` dark, and `AppTheme.errorColor` follows, so
  form validation text and error input borders match; dark theme got
  `errorColorDark` so the lifted tint keeps contrast on `#161616`.
- Swept every remaining raw `Colors.green` / `Colors.red` in `lib/`
  (friend-request accept/reject icons, email-confirmation success screens,
  discount/balance chips, delete & error icons, edit-profile error hints,
  receipt-scanner tints, quick-action modal) onto those tokens: **zero raw
  `Colors.green`/`Colors.red` left in `lib/`**, so the app now has one green
  and one red family to retune from `theme.dart`.
- Settle-up feedback is explicit now: the success snackbar is brand green with
  dark ink, the failure snackbar uses the washed-out red.
- The exported **PDF** follows the same palette: `PdfColors.green700` /
  `red700` in the bill summary became `PdfColor.fromInt(0xFF477326)` /
  `0xFFB0554D` (the app's exact values, kept deep enough to read on paper),
  so an exported statement and the screen agree.

## Verified
`flutter analyze` → 37 issues, **all** pre-existing `material_ui`
deprecation infos, 0 errors/warnings from app code.
`flutter test` → **27/27 pass** (15 original + 8 cache + 4 settlement payload).
Touched files are `dart format`-clean.

## Still open (not done here)
- `BalanceService.adjustBalance` is deliberately best-effort: it logs and
  continues, so a *ledger* write blocked by RLS would not fail the settle-up.
  Making it strict is a one-line change if you want the snackbar to report it.
- `PaymentService.createPayment` (legacy DAO, unused by the UI) sends the
  serial `id` explicitly — worth deleting or fixing if it is ever revived.
