# Mac cohesion handoff

The Windows reference is version 1.5.4 in `Windows/`. Work on the macOS app in `sunBEAR/sunBEAR.xcodeproj`; `sunBEAR 2/` is an older snapshot retained for comparison.

## Agreed appearance

- Dark forest-green header (#1E4235) with the sunBEAR name only; no subheading.
- Muted sage selection backgrounds (#E9EFEA), dark readable text and dark header-colored expansion arrows. Avoid bright blue selection highlights in the library.
- Collections and saved search titles in the left sidebar; record list and details in the main area.
- Clear primary import action, grouped download/export controls, and no persistent selection reminder in the record area.
- NYT sign-in and TimesMachine controls appear only when New York Times is selected.

## Agreed behavior

- Shift-click selects a range of search sessions in the left sidebar and shows their combined records. On Mac, use Command-click for independent selections, following platform conventions.
- The records list also supports range and independent selection. Downloads and exports act on selected records, or all visible records if none are selected.
- Loading is indeterminate during discovery. Once a total is known, advance progress after each record is processed, not when it starts. Explain failures separately; processed is not the same as successfully downloaded.
- NYT topic/search and article links produce metadata records. Available rendered article text can be saved as readable offline HTML with citation/source information.
- Log in inside the app's browser session. If article access is unavailable, pause for sign-in; Continue reloads and checks the same article. Stop cancels while preserving completed work.
- Preserve the existing library, exports, original licensing and the user's access controls.

## Validate on macOS

Inspect the current Swift implementation before changing it. Preserve its native library storage and integrations. Exercise actual mouse/keyboard selection events, including Shift ranges and Command toggling; tests of a selection helper alone missed a native Windows event-order bug.

Check progress, cancellation, login pause/resume and real account-specific article access. Live subscriber article completeness and EndNote HTML attachment import remain unverified on the Windows development machine. Do not infer that those integrations are validated from local parser tests.

See `Windows/README.md`, `Windows/VALIDATION.md`, `Windows/MainForm.cs`, `Windows/SessionTree.cs`, and the article/browser/scraper files for reference. Keep Mac keyboard conventions and native controls where they improve usability.
