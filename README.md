# ScheduleRsync

**Testing period:** the RsyncUI launch call is commented out. When a schedule fires, its URL appears as selectable text at the bottom of the main calendar. Only the latest triggered URL is displayed; it is cleared when the app restarts.

Standalone Apple Silicon (arm64) macOS 14+ scheduler extracted from RsyncUI. Open `ScheduleRsync.xcodeproj`, select the ScheduleRsync scheme, and run. Set your signing team for distribution. No Swift package dependencies are required.

The calendar supports once, daily, weekly, and repeating schedules, profile selection, upcoming occurrences, deletion, and automatic catch-up after waking. Closing the main window quits ScheduleRsync and cancels scheduling. The menu bar calendar is available while the app is running. Keep the app and its main window open and the Mac awake for on-time triggers. The app does not install a login item or wake the Mac.

## Source organization

The source folders are synchronized with Xcode automatically:

```text
ScheduleRsync/
├── App/                 App entry point, lifecycle, and menu bar
├── Models/              Schedule definitions and JSON models
├── Scheduling/          Schedule state, recurrence, and task runner
├── Storage/             JSON reading/writing and storage support
├── Utilities/           Date/string helpers and Mac identification
└── Views/
    ├── Calendar/        Calendar views and month layout
    ├── Components/      Reusable buttons and input controls
    └── Schedules/       Schedule editor and tables
ScheduleRsyncTests/
├── Calendar/            Calendar layout tests
├── Scheduling/          Schedule state and recurrence tests
└── Storage/             Storage compatibility and URL tests
```

## RsyncUI integration and storage

Each due schedule opens `rsyncuiapp://loadprofileandestimate?profile=Default`, substituting the selected profile with URL query encoding. This uses NSWorkspace's URL opening API, equivalent to `open "rsyncuiapp://loadprofileandestimate?profile=Default"`. RsyncUI must be installed and registered for that scheme; it owns estimation and synchronization.

ScheduleRsync reads and writes **the same file used by RsyncUI**: `~/.rsyncosx/<Mac serial>/schedule.json`. It preserves the JSON array and fields `id`, `profile`, `dateAdded`, `dateRun`, and `schedule`; older records without IDs are supported. Dates retain `dd MMM yyyy HH:mm` and recurrence values retain `once`, `daily`, and `weekly`. A missing profile means Default. Existing profile folders in the same Mac-specific directory populate the picker. Writes are atomic and serialized. No migration or copying of user data is performed. Avoid running an older RsyncUI version's scheduler alongside this app, since both could launch the same schedules and write the file.

The project is intentionally unsandboxed to retain access to the existing RsyncUI configuration directory. It doesn't modify task configurations or sync logs. Calendar display and recurrence expansion are retained from RsyncUI.

## Validation

```sh
xcodebuild -project ScheduleRsync.xcodeproj -scheme ScheduleRsync -destination 'platform=macOS' test
```

The test target contains the extracted scheduler tests plus checks for URL encoding and legacy schedule JSON compatibility. Storage tests use temporary files.

## Trigger lifecycle and testing

`Scheduling/GlobalTimer.swift` retains its existing facade name but uses a cancellable Swift task instead of a Foundation run-loop timer. Only one deadline wait is armed at a time. The task waits until the next occurrence or 30 seconds, whichever comes first, then checks the actual date before triggering anything. System clock changes also prompt a check. Task suspension does not occupy a thread. Delivery is best effort, not a real-time guarantee; a busy app or sleeping Mac can delay it.

Before sleep, the app cancels the pending wait. After wake, it consumes overdue occurrences and coalesces missed repeats to the latest missed occurrence per definition, then spaces eligible starts using the same planner. Missed repeats that cannot fit before their next occurrence are skipped. Future occurrences retain their original requested recurrence; conflicting starts are automatically spaced. Only the latest URL remains visible when several definitions trigger. Occurrences handled during this app session are tracked in memory so queue rebuilds and backward clock changes cannot replay them.

Closing the main window or quitting cancels the runner, clears its pending work, removes its sleep/wake and clock observers, and prevents late callbacks or file reads from restarting it. There are no installed LaunchAgents, helper processes, or background runners that survive app exit. The hourly calendar-horizon maintenance task is bound to the window and checks scheduler state before doing work. On relaunch, schedules are loaded afresh; elapsed occurrences while the app was closed are skipped.

URL-only testing remains enabled. Automated tests cover due-date checks, simultaneous profiles, wake catch-up, pauses during file updates, duplicate prevention after queue rebuilds, queue replacement, terminal shutdown, and actual asynchronous callback delivery. To validate on a real Mac:

1. Add a once schedule a few minutes ahead and leave the app open. Confirm its URL appears once when due.
2. Add a schedule, put the Mac to sleep before it is due, then wake it after the due time. Confirm its URL appears after wake. For a repeat schedule spanning multiple missed intervals, confirm there is one catch-up trigger and future times remain aligned.
3. Close the main window before another schedule is due. Confirm the app exits and no trigger occurs; reopen it after the due time and confirm that elapsed run is skipped.

## Building for Apple Silicon

Both Debug and Release configurations build arm64 only. Run `make debug` for a local unsigned app in `build/arm64/`, or `make test` to run the test target. Xcode 27 is required to build; the app runs on macOS 14 or later.

`make build` archives, exports a Developer ID app, submits it for notarization, staples it, and packages an arm64 DMG. It uses signing team `93M47F4H9T` and the existing `RsyncUI` notarization keychain profile. Override `DEVELOPMENT_TEAM`, `NOTARY_PROFILE`, or `CREATE_DMG` as needed. The default DMG helper is `../create-dmg/create-dmg`; a background image is used only when `images/background.png` exists. `make check NOTARY_ID=<submission-id>` retrieves a notarization log.

## Calendar

The calendar follows your system's first weekday and shows six complete weeks; adjacent-month days are dimmed. Every heading includes the month and year. Today is outlined, the selected run date is highlighted, and clock badges count scheduled profile runs on each day. Hover over a marked day to read its profiles and times. Select a day to update the native run-date picker. Browsing does not expand the execution queue. Only future occurrences in the current and next calendar month are generated; saved recurring definitions are retained.

## Repeat schedules

Select **Schedule → Repeat**, choose a profile and start date/time, and enter **Every … minutes**. Use whole minutes with a minimum of **30**; for example, **90** repeats every 1 hour 30 minutes. The schedule list shows **Every 90 min**, and calendar badges include each occurrence.

Repeat intervals measure elapsed time from the original start, including across daylight-saving changes. After a restart, future runs stay aligned with that start; elapsed runs are skipped. While the app remains open, wake catch-up triggers once per overdue definition. The schedule JSON has optional `repeatIntervalMinutes` and `repeatStartTimestamp` fields; older once/daily/weekly records remain readable. The original start timestamp preserves the exact instant when local clocks repeat an hour. URL-only testing mode remains enabled.

## Delete a schedule series

Select any run in the table and click **Delete series** (or press Delete), then confirm. Selecting several runs from the same series still deletes just its one definition. The app removes the selected definitions from `schedule.json`, rereads the updated file, rebuilds upcoming runs and the next deadline wait, removes missed runs belonging to the deleted series, and clears the last testing URL. Unrelated file records are preserved. If reading or writing fails, an error is shown and the existing schedule queue is restored.

## Automatic scheduling and spacing

The **Minimum between tasks** control sets a global start-to-start gap in whole minutes (1–1440), defaulting to **15 minutes**. SwiftUI `@AppStorage` saves changes in macOS UserDefaults automatically; no Save button is required. The same global gap applies to all profiles, including separate definitions for the same profile.

The **Quiet period** is enabled by default from **23:00 to 07:00** in local time. Its toggle and editable From/To times are saved automatically in UserDefaults. Starts within that period move to its end, while preserving the global gap. If that adjustment reaches the next occurrence in the series or exceeds the planning horizon, the occurrence is skipped. Equal From/To times mean no quiet period.

The planner processes requested times in order, with stable profile/series ordering for ties, and delays conflicts to the earliest allowed start. Yellow table text and calendar badges indicate adjusted occurrences; the Status column tooltip shows the requested time. A delay does not change the original recurrence anchor. A run that would reach its series' next occurrence, or exceed the end of next month, appears in red as **Skipped** and is excluded from execution and spacing calculations. Red rows can still be selected to delete their saved series.

The bounded plan is rebuilt on launch, additions, deletions, spacing or quiet-period changes, and hourly maintenance (including month rollover). Sleep and late delivery use the same global spacing and quiet period, with missed repeats coalesced to prevent a backlog. Runs elapsed while the app was closed are skipped on relaunch. The gap measures starts; this app does not receive synchronization completion feedback from RsyncUI.


### Compact scheduler window

The main window supports a 1,000 × 700-point layout with a compact calendar. Profile, recurrence, run date/time, repeat interval, and Add remain visible. Expand the gap/quiet-hours summary to edit scheduling rules and read their explanations. Calendar help contains the legend and planning horizon. Select a run and expand **Run details** to see its recurrence, full status, requested time, added date, and time remaining. The last testing URL is expandable and selectable. These layout changes preserve the existing scheduling and URL-only testing behaviour.
