# macOS guide

The maintained macOS project is `sunBEAR/sunBEAR.xcodeproj`. It uses SwiftUI for the interface, SwiftData for the local library, and WebKit for source browsing and authenticated imports.

## Import workflow

1. Choose a supported source.
2. Choose the folder where source files should be saved.
3. Browse or paste a supported search-results URL.
4. Set the number of result pages or batches to inspect.
5. Import the records and monitor progress in the status bar.

Each import creates a dated session in the library and a corresponding folder on disk. Use the session menu to rename or organize it, export its records, send supported references to EndNote, or reveal its folder in Finder.

## New York Times

Use **Search New York Times** rather than the generic URL import button. Sign in inside sunBEAR when required, run the search in the embedded browser, and choose **Import This Search** after results appear.

sunBEAR keeps one persistent WebKit session and uses that same browser instance to load result pages and articles. It does not save the account password. NYT controls session expiration, verification, subscriptions, and the content returned to the browser.

When **Save readable articles** is enabled, the complete article text available in the browser is stored in the record and written as a readable HTML file. If no article body is available, metadata or a description may still be saved and the record reports the article-page error. Scanned print-edition and TimesMachine material may require separate handling from ordinary web articles.

## Library and exports

- Collections group related import sessions.
- Command-click selects independent sessions; Shift-click selects a range using macOS conventions.
- The center table filters and sorts records from the selected session.
- TSV and EndNote exports use source-aware metadata.
- **Show Session Folder in Finder** is the supported way to access saved HTML and downloaded files.

## Development

Run the unit tests before committing:

```bash
xcodebuild test \
  -project sunBEAR/sunBEAR.xcodeproj \
  -scheme sunBEAR \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:sunBEARTests
```

Live authentication, publisher downloads, and EndNote automation must also be verified on a Mac with the relevant account or application.
