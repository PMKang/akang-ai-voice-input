# Known issues

## A single Fn / Globe shortcut cannot be intercepted reliably on every Mac

**Status:** Open. The first release recommends `Option + Command`.

### Symptoms

- Fn can trigger voice input, but some macOS devices also switch the system input method.
- Long-press and short-press behavior may differ.
- The result depends on the focused control, keyboard hardware, and macOS session state.

### Already verified

- Accessibility and Input Monitoring permissions are granted.
- The implementation uses native `CGEventTap`, `headInsertEventTap`, and `defaultTap`.
- Both HID and Session tap locations have been tested.
- `keyDown`, `keyUp`, and `flagsChanged` are observed to cover Fn press, release, and modifier-state changes.
- `tapDisabledByTimeout`, `tapDisabledByUserInput`, health checks, and wake-from-sleep refreshes are handled.
- Changing `AppleFnUsageType`, restarting input-source services, and restoring the input method afterward cannot consistently eliminate the system switching overlay in every environment.

### Current decision

- `Option + Command` is the default shortcut for reliable cross-app recording control.
- Fn remains an experimental option rather than the default.
- A future GitHub Issue can publish a minimal reproduction with macOS version, keyboard model, and event logs for developers familiar with Quartz Event Services, IOHID, or DriverKit.

### Safety boundary

The app prefers public macOS APIs and does not use kernel extensions or third-party proprietary code.
