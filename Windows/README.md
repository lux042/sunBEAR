# sunBEAR for Windows — 1.5.4

A research library for collecting article and document metadata, saving accessible files, and exporting references to EndNote.

## Requirements and build

Windows 10 or 11 (x64), Microsoft Edge WebView2 Runtime, and the .NET 8 SDK to build from source.

Run `./build.ps1` in PowerShell from this folder. It restores the pinned dependencies and creates a self-contained app in `publish/`. Open `publish/sunBEAR.exe`; keep its companion files together. The published app includes the .NET runtime. Builds are portable and unsigned.

## Collect research

1. Choose CIA FOIA, JSTOR, ERIC, PubMed, National Archives, or New York Times.
2. Paste a supported search link or use **Browse source** to find a page in sunBEAR's browser.
3. Choose the number of search pages and download options, then click **Import records**. The browser also has **Import this page**.
4. Select a saved search session in the left sidebar to view its records. Organize sessions with **+ Collection** and **Manage**.

**Shift-click** selects a range of search sessions on the left. **Ctrl-click** adds or removes individual sessions. Their records appear together in the table. The records table also supports Ctrl/Shift selection, Ctrl+A to select all, and Escape to clear.

Record downloads and exports use selected rows when present, otherwise all visible rows. Session-level export remains a separate action in Manage.

## New York Times

The Windows app accepts NYT topic/search links, dated article links, and individual TimesMachine article links. Whole newspaper issue viewers are not article records.

Select **New York Times** to reveal **NYT sign in**, **TimesMachine**, and **Save article pages**. Sign in inside sunBEAR; another browser's login is separate. When readable article text is unavailable, the task pauses. Complete sign-in or check access, then choose **Continue after sign-in** to reload and check the same article. **Stop task** cancels the pause. A subscription may be required.

**Save article pages** saves available rendered article text as readable offline HTML, along with its citation and source link. For existing records, use **Downloads / files > Download article pages**. **Read saved article** opens the local copy. A repeated download updates that record's page; a failed attempt preserves the earlier saved copy.

Saved HTML is not a screenshot or an exact copy of the original layout. It excludes images, video and interactive content. Rendered text alone cannot prove the article is complete; compare an initial saved page with what your account can read. Access controls are not bypassed. Scanned TimesMachine articles may offer PDFs rather than readable text.

NYT pagination follows available next-page links, Show More/Load More controls, or scrolling, up to the chosen number of batches. Topic pages are not guaranteed complete historical searches. Use date-filtered NYT searches when appropriate.

## PDFs and progress

The app uses offered PDF links and the embedded browser session, with a direct-download fallback. **Downloads / files > Retry missing PDFs** retries missing or failed files. Already saved files are skipped. Check record notes or **Open PDF in browser** when a download needs attention. Browser PDF transfers have a 128 MB limit.

Progress is indeterminate while discovering records. Once the total is known, the bar advances after each record is processed. Processed counts include items needing attention; the final message reports failures separately. It is not a byte-download percentage. Stop retains completed records and files.

## Export

The **Export…** menu offers TSV, EndNote tagged files, EndNote XML, and Send to EndNote.

- For `.enw`, use EndNote's **EndNote Import** filter if opening the file does not import it automatically.
- For XML, use **EndNote generated XML**.
- **Send to EndNote** opens the saved `.enw` through the Windows file association; sunBEAR cannot confirm the import completed.
- NYT records use the Newspaper Article reference type. Article text is separate from the abstract; saved pages are included as local attachment references.
- The original custom CIA reference type is retained and must be configured in EndNote.
- TSV retains the original 16 columns, adding six NYT columns when applicable.

Moving saved files can break attachment links. Live EndNote acceptance of HTML attachments has not been verified.

## Library and saved files

The library and browser profile are stored in `%LOCALAPPDATA%\sunBEAR`. The previous library save is retained as `library.json.bak`. Close the app before backing up or restoring this folder. Browser profiles contain signed-in sessions and should not be shared.

Downloads default to `Documents/sunBEAR Downloads`, with a folder per import. Change this with **Save location…**. Deleting a session from the library leaves downloaded files on disk. Repeated imports create separate sessions. The Windows app does not migrate a Mac SwiftData library.

## Validation

The local test suite covers parsers, exports, PDF validation, article capture and persistence. UI checks cover session range selection through native mouse messages, Ctrl toggling, record-selection scope, progress and sign-in pause/cancel behavior. See [VALIDATION.md](VALIDATION.md).

To run the deterministic tests after building:

```powershell
Start-Process .\publish\sunBEAR.exe -ArgumentList '--test', 'C:\path\test-results.txt' -Wait
```

Live NYT subscriber article capture, updated PDF downloads and EndNote integration still require verification on the user's computer. Website layout changes can require parser updates.

## Source layout

- `MainForm.cs`, `SessionTree.cs`: library interface and sidebar selection.
- `BrowserPane.cs`, `Scraper.cs`: browser session, discovery and downloads.
- `Parser.cs`, `NewYorkTimesParser.cs`: source-specific parsing.
- `ArticlePages.cs`: rendered text capture and offline HTML.
- `Models.cs`, `Exports.cs`: persistence and reference exports.
- `SelfTests.cs`, `*Tests.mjs`: local validation fixtures.

MIT licensed; original sunBEAR attribution is preserved in [LICENSE](LICENSE).
