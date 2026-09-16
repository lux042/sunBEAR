# sunBEAR for Windows — 1.3.0

## Article downloads and Library loading screen

NYT imports now offer **Save article pages**, enabled by default. This opens each article, collects its rendered article-body paragraphs and headings, and saves a readable offline **HTML** page in the session's download folder. Available article text is stored in the library, appears beneath the citation details, and is searchable.

For records already imported, select their session and click **Download article pages**. This processes the visible NYT records without creating duplicate records. Use **Open saved page** to read a downloaded copy. Repeating the download updates that record's HTML copy; a failed attempt preserves its previously saved text and page.

Imports, PDF retries, and article-page downloads show a Library loading panel with the current operation and record count. The Stop button remains available above it. Completion, cancellation and errors restore the normal Library view.

Capture reads available, rendered article elements; it does not reveal hidden text or remove access controls. An access prompt or missing body produces a page-specific error. TimesMachine scans may have a downloadable PDF but no readable article-body text. Offline HTML contains text and citation details, not a screenshot, original site layout, images, video or interactive content. A rendered body cannot independently prove that the publisher supplied the complete article, so check an initial saved page against what you can read in the browser.

## New York Times and TimesMachine

Choose **New York Times** in the source list. Supported inputs include:

- Topic pages, including `https://www.nytimes.com/topic/destination/ecuador`.
- Standard NYT search URLs, including date filters for historical searches.
- Individual dated NYT article URLs.
- Individual TimesMachine archive article URLs, plus archive search URLs containing a query. Whole newspaper issue viewers are not imported as article records; select an article first.

Click **Browse** for NYT search or **TimesMachine** for the archive. Sign in within sunBEAR if your account requires it. Use **Import this page** from the browser, or paste the URL in the Library view and click **Import**.

For NYT lists, **Pages** means the first loaded group plus up to the selected number of result batches, capped at 10. The app follows a next-page link when provided, uses visible Show More/Load More buttons, or scrolls an on-demand list. If no further article links appear, collection stops. A page you have already expanded in sunBEAR starts with all its currently loaded articles. Topic pages are lists, not guaranteed complete searches of the newspaper's entire history; use date-filtered search for historical research.

Records include available title, byline, publication date, description, section, print-page references, and article URL. With Save article pages enabled, they also include available article-body text and an offline page. EndNote exports use **Newspaper Article** with separate authors and available print pages. The abstract stays separate from the article text; saved HTML is included as a local file-attachment reference. TSV exports containing NYT records append Author, Section, Print Pages, Article Text, Saved Page and Page Status after the original 16 columns; exports without NYT records retain the original layout.

The app downloads only PDF links provided by the NYT/TimesMachine page, including archive PDF referral links. It may follow an article's TimesMachine link to discover the offered PDF. It does not create a PDF from a webpage or invent archive download URLs. If no PDF link is present, the citation is saved and the table says **No PDF link**. Account access and download limits still apply.

The user has confirmed NYT article metadata importing on their PC. Article-text capture and offline HTML downloads passed controlled tests but still need live account-specific verification. The live Ecuador topic page could not be inspected through the development web tool.

## PDF download update

Version 1.0.1 first requests PDFs through sunBEAR's embedded browser session, retaining browser-managed access state. Direct downloading remains a fallback for sources where browser fetch is unavailable, including cross-origin restrictions.

To repair an existing import, select its session and click **Retry PDFs**. This retries missing or failed PDFs across the visible records without creating new records. Existing saved files are skipped, and successful retries clear the error status. Stop cancels the retry while retaining completed downloads. The existing library is read automatically; no re-import is required.

If a record still needs attention, select it and read the download notes. **Open PDF in browser** can reveal a site verification page, an unavailable document, or an access requirement. This update does not bypass those requirements. Browser transfers are limited to 128 MB per PDF; larger files can be downloaded manually.

Windows port of the supplied sunBEAR Swift project. It uses C#/.NET 8, Windows Forms, Microsoft Edge WebView2, and Html Agility Pack. The original application's MIT license and attribution are retained.

## Run

Extract the entire Windows ZIP, then open `sunBEAR.exe`. Keep the accompanying files beside it. This package targets Windows 10/11 on x64 PCs and includes the .NET runtime. It is a portable application, not an installer, and is not code-signed.

The embedded browser requires Microsoft's [Evergreen WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/). If browser startup fails, check that the runtime is installed and that the application can write to its profile folder.

## Use

1. Choose CIA FOIA, JSTOR, ERIC, PubMed, National Archives, or New York Times and click **Browse**.
2. Run a search. Sign in or complete any site verification in sunBEAR's browser if required.
3. Click **Import this page**, or paste a supported URL into the main window. Choose 1–10 pages and whether to download PDFs, then click **Import**.
4. Saved sessions appear in the left panel. Use **New collection** and **Actions** to organize, move, rename, or remove sessions. Removing a session does not delete downloaded files.
5. Filter the table and select records to export. With no rows selected, export uses all visible records. Choosing a collection displays its sessions' records together. The Actions menu can export a separate TSV for each session.
6. Use **Stop** to cancel. Records already saved remain in a session marked partial.

PDFs are saved in a folder per import under Documents/sunBEAR Downloads, unless you choose another destination. A failed PDF download is recorded in the record details; metadata remains available. **Open PDF in browser** lets you sign in or accept a site's download terms before trying another import. It may open a site's download dialog. Subscription or blocked content is not bypassed.

## EndNote

- **Export EndNote** writes `.enw` tagged records. In EndNote for Windows, use **File > Import > File** and select the **EndNote Import** filter if opening the file does not import it automatically.
- **Send to EndNote** saves an `.enw` file and asks Windows to open its associated application. EndNote must be installed and associated with `.enw`. The app cannot confirm that EndNote completed the import.
- **Export EndNote XML** writes XML for the **EndNote generated XML** import option.
- The original custom **CIA** reference type (XML type 40) is preserved. Configure that custom reference type in your EndNote library to match the original workflow. Other sources use Journal Article, Book, Report, or Generic as appropriate.
- TSV retains the original 16-column field order, including repeated Notes and URL headers, with six appended columns when NYT records are included. Local PDF and saved-page references in exports use Windows paths or file URIs. Moving those files can break attachment links. Live EndNote acceptance of HTML attachments has not been verified here.
- The Mac version's AppleScript automation is replaced by Windows file association/manual import. Live EndNote import was not verified in this environment.

## Local data and backup

The library lives at `%LOCALAPPDATA%\sunBEAR\library.json`. The previous saved copy is `library.json.bak`; the browser's own profile is in the `Browser` subfolder. Quit sunBEAR before backing up or restoring this folder. A damaged library produces an error rather than silently resetting it. Browser profiles can contain signed-in sessions, so do not share them with others.

This Windows build does not migrate an existing Mac SwiftData library. Downloaded PDFs and exported reference files can be transferred separately. Repeated imports create separate sessions and do not deduplicate across sessions.

## Validation and limitations

See `VALIDATION.md`. Automated checks cover six source parsers, paging, exports, PDF validation, browser-fetch logic, article capture and library persistence. The Library and loading panel were rendered and visually checked on Windows. The user's reports confirm CIA and NYT metadata imports on their PC. WebView2 initialization failed in the execution environment with `E_UNEXPECTED`; live article capture, updated PDF downloads and EndNote integration remain unverified here. Website layout changes may require parser updates.

## Build from source

Install the .NET 8 SDK on Windows and run `build.ps1` from this folder. It restores the two pinned NuGet packages and publishes a self-contained x64 app into `publish`. Internet access is needed for the initial package restore.

```powershell
dotnet publish .\sunBEAR.csproj -c Release -r win-x64 --self-contained true -o .\publish
```

Run the deterministic tests with an absolute report path:

```powershell
Start-Process .\publish\sunBEAR.exe -ArgumentList '--test', 'C:\path\test-results.txt' -Wait
```

For isolated application/browser integration validation, create an empty writable folder and pass `--data-dir` and `--smoke-test` with separate paths. The smoke test intercepts its CIA requests with synthetic fixtures, saves a test record, checks cancellation, captures the form, and exits. It never loads a real user library. Do not use an existing library folder for that mode.

## Implementation

- `Models.cs`: data models, atomic replacement of the library file, backups, source validation, and Windows-safe paths.
- `Parser.cs`: source-specific record discovery, paging and metadata extraction, ported from the supplied Swift parsers.
- `NewYorkTimesParser.cs`: NYT topic/search discovery, article and archive metadata, and offered PDF links.
- `ArticlePages.cs`: visible article-text extraction, HTML encoding, offline page saving and capture status.
- `BrowserPane.cs` / `Scraper.cs`: browser profile, page loading, cancellation, authenticated downloads and PDF validation.
- `Exports.cs`: TSV, EndNote tagged and XML exports.
- `MainForm.cs`: Windows interface and library management.
- `SelfTests.cs`: deterministic checks based on original Swift test cases plus Windows-specific coverage.

Browser API documentation: [Microsoft WebView2 environment creation](https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2environment.createasync). EndNote filter: [EndNote Import](https://endnote.com/downloads/filters/endnote-import/).

NYT archive information: [New York Times Archived Articles and TimesMachine](https://thenewyorktimeshelpcenter.helpjuice.com/115014772767-New-York-Times-Archived-Articles-and-TimesMachine). Newspaper XML type mapping checked against [Zotero's EndNote XML translator](https://github.com/zotero/translators/blob/master/Endnote%20XML.js).


Version 1.3.0: Click NYT sign in and log in inside sunBEAR before downloading article pages. Your normal browser login is separate. When readable article text is unavailable, work pauses in the Browser tab. Complete sign-in or verify access, then choose Continue after sign-in; sunBEAR reloads and checks the same article. Stop cancels the pause. A subscription may be required. Scanned archive articles may offer PDFs instead of readable text.

Progress is indeterminate while discovering the list, then shows processed records divided by the discovered total. Counts advance after processing and include failed items; the final message reports failures separately. This is not a byte-download percentage or a guarantee of full article completeness.

Validation: local parser/export/file tests and rendered UI checks passed. Live NYT authentication and subscriber article capture require verification on the user computer; WebView2 cannot initialize in the test sandbox.


Version 1.4.0: refreshed library with larger actions, grouped import options, empty-library guidance, and Export and Downloads / files menus. Progress and sign-in behavior retained.


Version 1.5.0 selection: Ctrl-click toggles individual rows; Shift-click selects a contiguous range using native Windows table selection. Ctrl+A or Select all selects visible records; Escape or Clear clears the selection. The selected count is shown above the table. Downloads, PDF retries and record exports use selected records when present, otherwise all visible records. Export each session remains a session-level action.
