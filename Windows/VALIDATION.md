# Windows build 1.3.0 validation

## Passed

- Release build targeting `win-x64`, with bundled .NET runtime.
- Compiler: 0 warnings and 0 errors.
- 23 deterministic C# test groups, 0 failures:
  - Supported search URLs and rejection of lookalike hosts.
  - CIA links, duplicate removal and paging.
  - CIA field order, metadata, abstract and PDFs.
  - JSTOR custom elements and canonical links.
  - JSTOR metadata, encoded abstracts and PDF discovery.
  - ERIC links, paging, metadata and hosted PDFs.
  - PubMed metadata, PMC discovery and paging.
  - National Archives metadata and paging.
  - NYT topic, search, direct article and TimesMachine URL acceptance and rejection.
  - Topic article extraction, duplicate/tracking removal, and navigation-link exclusion.
  - NYT structured metadata, authors and print pages.
  - Legacy NYT metadata and archive date fallback.
  - Publisher-provided TimesMachine PDF links and intact referral parameters.
  - Newspaper Article EndNote mapping, authors, year, section, pages and extended TSV.
  - Offline HTML encoding, text persistence, repeat-save behavior and attachment references.
  - Rejection of access-blocked, empty or mismatched article captures, preserving previous saved text.
  - All 16 TSV columns in the original order.
  - EndNote tagged fields, URL order and local attachment paths.
  - EndNote XML escaping, control-character removal and attachment URIs.
  - Windows-safe filenames, including reserved device names.
  - Browser-fetch response decoding and actionable error reporting.
  - PDF signature validation, rejection of HTML responses, collision handling and cancellation.
  - Library save/reopen, previous-version backup and corrupt-file protection.
- Windows form constructed and rendered. The resulting image was inspected and clipped controls corrected.
- Four JavaScript test groups pass using controlled responses: credential-preserving fetch options, exact PDF bytes across base64 chunk boundaries, rejection of HTML and HTTP errors, and cancellation. These test the browser-fetch script, not a live CIA request.
- Three JavaScript result-expansion tests pass: exact result-control selection, disabled/hidden control exclusion and scroll fallback. These do not establish compatibility with current live NYT markup.
- Four article-capture JavaScript tests pass: rendered text/headings, hidden-text exclusion, access prompt detection, inactive-gateway handling and clipped/non-article content filtering.
- Library and loading-panel render checks pass. The loading view replaces Library content, displays operation progress, leaves Stop available, and restores Library content when dismissed. The rendered loading panel was visually inspected.
- The user's existing library was inspected read-only: CIA metadata records were saved, while the original downloader recorded non-PDF responses for its PDF links. No user records were modified during development.

## Not verified

- The user supplied a successful NYT article metadata record, confirming that workflow on their PC. Live article-body completeness, offline page downloads, full topic coverage and TimesMachine downloads remain unverified here. Test fixtures are synthetic.

- Browser-driven import integration: the installed WebView2 runtime failed during controller creation with COM error `0x8000FFFF (E_UNEXPECTED)` in the execution environment. No successful browser integration test is claimed.
- The updated browser-session PDF retry against live CIA URLs. The user's report confirms that browser-driven CIA metadata importing works on their PC; successful PDF recovery has not yet been confirmed.
- Live searches, sign-ins, subscription access, redirects, and authenticated PDF downloads across all six services.
- Live import into EndNote. Tests validate generated export structure and fields, not EndNote's acceptance of a particular user's custom reference types or attachment handling.
- A separate clean Windows PC, ARM64 hardware, code signing, installer behavior or Mac-library migration.

## Suggested first-use acceptance check

1. Extract the complete ZIP and launch `sunBEAR.exe` on an x64 Windows PC.
2. Confirm the Browser tab opens. Run a small search on a source you use, with one page and PDFs disabled.
3. Confirm titles and metadata against the original website, then restart the app and verify the session remains.
4. Import a record with an accessible PDF and confirm the saved PDF opens.
5. Export a few records to EndNote, verify the field mapping and attachment links, and verify the CIA custom reference type if applicable.

Do not treat fixture-based parser tests as proof that current live website layouts are compatible.


Version 1.3.0: Click NYT sign in and log in inside sunBEAR before downloading article pages. Your normal browser login is separate. When readable article text is unavailable, work pauses in the Browser tab. Complete sign-in or verify access, then choose Continue after sign-in; sunBEAR reloads and checks the same article. Stop cancels the pause. A subscription may be required. Scanned archive articles may offer PDFs instead of readable text.

Progress is indeterminate while discovering the list, then shows processed records divided by the discovered total. Counts advance after processing and include failed items; the final message reports failures separately. This is not a byte-download percentage or a guarantee of full article completeness.

Validation: local parser/export/file tests and rendered UI checks passed. Live NYT authentication and subscriber article capture require verification on the user computer; WebView2 cannot initialize in the test sandbox.


Version 1.4.0: refreshed library with larger actions, grouped import options, empty-library guidance, and Export and Downloads / files menus. Progress and sign-in behavior retained.


Version 1.5.0 selection: Ctrl-click toggles individual rows; Shift-click selects a contiguous range using native Windows table selection. Ctrl+A or Select all selects visible records; Escape or Clear clears the selection. The selected count is shown above the table. Downloads, PDF retries and record exports use selected records when present, otherwise all visible records. Export each session remains a session-level action.
