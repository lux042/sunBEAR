# sunBEAR

A desktop research library for collecting document and article metadata, saving accessible source files, and exporting references to EndNote.

## Choose your platform

| Platform | Source | Getting started |
| --- | --- | --- |
| Windows 10/11, x64 | [Windows](Windows/) | [Windows guide](Windows/README.md), current version **1.5.4** |
| macOS | [sunBEAR](sunBEAR/) | Open `sunBEAR/sunBEAR.xcodeproj` in Xcode |

The Windows application is a C#/.NET 8 Windows Forms port. The original macOS application uses Swift, SwiftUI and SwiftData. Features and storage formats differ between platforms; Windows does not migrate a Mac SwiftData library.

## Windows features

- Import research from CIA FOIA, JSTOR, ERIC, PubMed, National Archives and the New York Times.
- Collect available metadata and offered PDFs; save accessible NYT article text as readable offline HTML.
- Sign in through the embedded browser. NYT-specific controls appear when New York Times is selected.
- Organize saved searches into collections. Shift-click search titles in the left sidebar to select a range; Ctrl-click to choose individual searches.
- Filter and select records for downloads and export. Progress reflects processed records, with failures reported separately.
- Export TSV, EndNote tagged files and EndNote XML.

See the [Windows guide](Windows/README.md) for exact controls, download behavior, account access and local data locations.

## Build for Windows

Install the .NET 8 SDK on Windows and Microsoft's Edge WebView2 Runtime, then run:

```powershell
cd Windows
.\build.ps1
```

Open `Windows/publish/sunBEAR.exe` and keep its companion files together. The build is self-contained for .NET, portable and unsigned. The initial NuGet restore requires internet access.

## Repository layout

- `Windows/` — current Windows source, build script, tests and usage documentation.
- `sunBEAR/` — current macOS Xcode project and tests.
- `sunBEAR 2/` — older macOS source snapshot retained for comparison; use `sunBEAR/` for current macOS development.
- `Documentation/` — original project planning documents, which may describe historical plans.
- `SampleData/` and `Scripts/` — supporting project directories.

Generated application bundles, disk-image staging files, old ZIP snapshots and local EndNote libraries do not belong in the current source tree. Removed files remain recoverable from Git history. Future downloadable builds should be attached to GitHub Releases.

## Validation and limitations

Windows has deterministic parser, export, PDF-validation and persistence tests, browser-script fixtures, and UI checks for selection, progress and sign-in pauses. See [Windows validation notes](Windows/VALIDATION.md).

Live NYT subscriber text capture, updated PDF downloads and EndNote integration still require verification on the user's computer. Website changes can require parser updates. Available rendered article text is not a guarantee of completeness. The application does not bypass subscriptions or access controls; use sources within the access granted to your account.

## License

[MIT](LICENSE). Original sunBEAR attribution is preserved.
