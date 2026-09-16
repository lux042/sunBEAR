# Mac feature alignment — Windows 1.6.0

Compared with lux042/sunBEAR main at dbcbc2d9b7a34aa98d3c78e97b21aefa52947f24 on 2026-09-16.

Ported: three-column library, session filtering and sorting, bulk session move/export/EndNote/delete, collection contents selection and two deletion choices, current-page NYT import with query recovery, games filtering, additional visible article paragraph layouts, article text retention independent of HTML saving, browser reload, JSTOR/PMC PDF preparation, and per-record PDF choice.

Retained: muted sage Windows selection, Ctrl/Shift sidebar selection, source-specific NYT sign-in visibility, persistent browser login, processed-record progress and pause/resume access workflow.

Windows uses WebView2 and JSON library storage; macOS uses WebKit and SwiftData. This release aligns workflows but does not migrate a Mac library or browser login. Only accessible rendered article text is captured. Offline HTML contains text and citation information, not the original page's media or layout.

Local checks pass; live account-dependent NYT and PDF access still require checking on the user's Windows installation. See VALIDATION.md.
