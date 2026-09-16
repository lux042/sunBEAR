# Windows 1.6.0 validation

- Release publish for Windows x64 with bundled .NET: succeeded, 0 warnings and 0 errors.
- 27 C# test groups passed: source parsing, URL validation, exports, article storage, PDF handling, library persistence, NYT rendered-search query recovery, games filtering, PDF preparation, and session filtering/sorting/moving/deletion.
- 12 JavaScript fixture groups passed: 5 article-capture, 4 browser PDF-fetch, and 3 NYT result-expansion checks. Article checks include standalone visible paragraphs and exclusion of hidden or clipped text.
- Native Windows form checks passed: Ctrl/Shift sidebar selection, multi-search record union, selection preservation after sorting and right-click, search filtering, grid selection scope, 25% processed progress, loading restoration, and access pause/resume/cancel.
- Three-column library rendered and visually inspected at normal and compact window sizes.
- App and source ZIP integrity checked.

## Limits

The installed WebView2 runtime cannot initialize in this execution sandbox (0x8000FFFF E_UNEXPECTED). Therefore live browser imports, NYT login/subscriber article completeness, JSTOR/PMC preparation and authenticated downloads are not claimed as verified. Tests use controlled fixtures. The user previously confirmed NYT metadata importing on their PC.

EndNote export structure is tested; live EndNote import and attachment acceptance are not. No Mac library migration, code signing, installer, ARM64 or separate clean-PC test is included.

## First-use check

Close the previous app and launch this version with all companion files intact. Check an existing library, then import one page from a source you use. For NYT, sign in inside sunBEAR and compare one saved article against what your account can read. For JSTOR/PMC, prepare a PDF in the browser and verify a download. Export a few records to EndNote and check fields and attachments.
