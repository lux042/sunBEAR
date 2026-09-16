# New York Times in sunBEAR 1.3.0

1. Close the previous sunBEAR window and open this version's `sunBEAR.exe`. Your existing library remains in the same location.
2. Choose **New York Times**.
3. Paste `https://www.nytimes.com/topic/destination/ecuador` in the URL field.
4. Start with **Pages: 1** and **Save article pages** checked, then click **Import**. If NYT asks you to sign in or verify access, use the Browser tab and then retry.
5. For a larger collection, choose more pages. On topic lists this counts result batches loaded by Show More, Load More, or scrolling; it does not promise an exhaustive historical search.
6. Select the saved session and use **Export EndNote**, **Export EndNote XML**, or **Export TSV**.

**For articles you already imported:** select the session and click **Download article pages**. The Library shows a loading screen and progress. Use **Open saved page** on a record to open its offline HTML copy. Article text is also shown below its citation details. Stop retains completed downloads.

For historical material, use NYT search with a date range or open **TimesMachine**, select an individual article, and click **Import this page**. Whole issue viewers are not treated as individual articles.

**PDF behavior:** Downloads use links the publisher provides. Articles without a downloadable PDF are retained as citation records marked **No PDF link**. Where a TimesMachine PDF is offered, normal account access is required. The app does not turn article webpages into PDFs.

**Testing status:** Citation, capture and export tests pass, and the loading screen was visually checked. The user has confirmed NYT metadata imports. Live article-text completeness and account-dependent downloads still need verification on the user's PC.


Version 1.3.0: Click NYT sign in and log in inside sunBEAR before downloading article pages. Your normal browser login is separate. When readable article text is unavailable, work pauses in the Browser tab. Complete sign-in or verify access, then choose Continue after sign-in; sunBEAR reloads and checks the same article. Stop cancels the pause. A subscription may be required. Scanned archive articles may offer PDFs instead of readable text.

Progress is indeterminate while discovering the list, then shows processed records divided by the discovered total. Counts advance after processing and include failed items; the final message reports failures separately. This is not a byte-download percentage or a guarantee of full article completeness.

Validation: local parser/export/file tests and rendered UI checks passed. Live NYT authentication and subscriber article capture require verification on the user computer; WebView2 cannot initialize in the test sandbox.


Version 1.4.0: refreshed library with larger actions, grouped import options, empty-library guidance, and Export and Downloads / files menus. Progress and sign-in behavior retained.
