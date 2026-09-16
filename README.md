# sunBEAR

## About

sunBEAR is a desktop research library for collecting records from public archives, academic databases, and newspapers. It keeps related searches together, saves source files that the user is authorized to access, and exports citations for spreadsheets and EndNote.

Native applications are maintained for macOS and Windows. Both versions respect publisher authentication and access controls; sunBEAR does not bypass subscriptions, paywalls, or download restrictions.

## Supported sources

- CIA FOIA Reading Room
- JSTOR
- ERIC
- PubMed and PubMed Central
- U.S. National Archives
- The New York Times

Source websites change over time. A parser may need updating when a provider changes its markup or authentication flow.

## Platform status

| Platform | Implementation | Getting started |
| --- | --- | --- |
| macOS | SwiftUI, SwiftData, and WebKit | Open [`sunBEAR/sunBEAR.xcodeproj`](sunBEAR/sunBEAR.xcodeproj) in Xcode. See the [macOS guide](Documentation/MACOS.md). |
| Windows 10/11 x64 | C#/.NET 8 Windows Forms and WebView2 | See the [Windows guide](Windows/README.md). Current version: **1.6.0**. |

The two applications use native platform storage and do not share or migrate their libraries automatically.

## macOS highlights

- Native three-column library for collections, saved searches, records, and record details.
- Embedded, persistent browser session for authenticated source access.
- New York Times search import from the rendered results page, including searches whose query is not shown in the address bar.
- Full available NYT article text stored in the record and optionally saved as readable HTML.
- Source-aware TSV and EndNote exports.
- Downloaded files grouped in a folder for each import session.

To import from the New York Times, choose a save location, open **Search New York Times**, sign in if required, run the search inside sunBEAR, and choose **Import This Search**. The same embedded browser is used for discovery and article loading so its authenticated session remains consistent. NYT may still expire a session or request verification.

## Build and test on macOS

Requirements: a current version of Xcode with the macOS SDK.

```bash
xcodebuild test \
  -project sunBEAR/sunBEAR.xcodeproj \
  -scheme sunBEAR \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:sunBEARTests
```

For normal development, open the Xcode project, select the `sunBEAR` scheme, and run it on **My Mac**.

## Windows highlights

Windows 1.6.0 brings the Mac library workflows to Windows: a three-column layout, saved-search filtering and sorting, bulk session actions, rendered NYT search imports, optional offline article pages, and JSTOR/PMC PDF preparation. Ctrl/Shift selects multiple saved searches. See the [Windows guide](Windows/README.md) and [Mac feature comparison](Windows/MAC-PARITY.md).

## Build for Windows

Install the .NET 8 SDK and Microsoft Edge WebView2 Runtime, then run:

```powershell
cd Windows
.\build.ps1
```

Open `Windows/publish/sunBEAR.exe` and keep its companion files together. The initial NuGet restore requires internet access. See [Windows/VALIDATION.md](Windows/VALIDATION.md) for tested behavior and known limitations.

## Data, authentication, and privacy

- Searches, records, and file paths are stored locally.
- Downloads and readable HTML are written to the folder selected by the user.
- Website sign-in is handled by the embedded browser. sunBEAR does not store account passwords.
- Captured article text is limited to content delivered to the signed-in browser session.
- Live subscriber access, publisher downloads, and EndNote integration depend on the user’s local accounts and installed applications.

## Repository layout

- `sunBEAR/` — current macOS application and tests.
- `Windows/` — current Windows application, tests, build script, and Windows documentation.
- `Documentation/` — current cross-platform and macOS documentation.

Generated builds, downloaded research files, local databases, disk-image staging folders, and old source snapshots are intentionally excluded. Previous files remain available through Git history and downloadable builds should be published through GitHub Releases.

## License

[MIT](LICENSE). Original sunBEAR attribution is preserved.
