# Handoff · Project site, README and search visibility (`site/`, `README*.md`)

Written by: Claude Code - Claude Opus 5.5 · 2026-11-15
Plan and live status table (owner's doc): https://claude.ai/artifact/US8VwUcxesXzgqZ7f8QqTH

Goal: people who search for FiveM scripts in Thai or English find nakara-oss, and the first thing they see is
that every script can be checked before it goes on a server ("ตรวจได้ก่อนลง server").

## Status now

| Wave | What | State | Evidence |
|---|---|---|---|
| W1 | README.md + README.th.md with the "🏗️ Trust Architecture" diagram (`docs/assets/trust-architecture-{en,th}.svg`), GitHub Pages site (Thai at `/`, English at `/en/`), `sitemap.xml`, `robots.txt`, `llms.txt`, `.github/workflows/pages.yml` | merged · live | #46 `6a46ecc` |
| Redesign | site restyled after the owner rejected the first look (dark warm charcoal + amber, Anuphan / IBM Plex Sans Thai / JetBrains Mono), animated Trust Architecture lane with pause button (`site/flow.js`) | merged · live | #47 `d102591` |
| W2 | pages `/cargen-crash/` and `/safety-scanner/` (TH + EN), social preview `docs/assets/og.svg` (rendered to `/og.png` at deploy), Search Console ownership meta | merged · live | #48 `f85d1af`; CI run 43698457861 (5 jobs success); Pages run 43698581997 success |
| W2 | repo description (TH + EN), 18 topics, homepage URL, social preview image | done (repo settings, not in git) | `gh repo view aeterna/nakara-oss --json description,homepageUrl,repositoryTopics,usesCustomOpenGraphImage` |
| W2 | Google Search Console: URL-prefix property `https://aeterna.github.io/nakara-oss/`, HTML-tag verified, `sitemap.xml` submitted | done 2026-11-15 | Search Console in the `fivem.tanakon.dev` Google account |
| W3 | measure after 4 weeks (impressions, queries, stars, npm downloads) ≈ 2026-12-13, then adjust the keyword map | not started | baseline in the plan doc §08 |
| W3 | in-browser safety scanner (drop a zip, scan locally, nothing uploaded): needs an ADR first (split `node:fs` into an adapter, unzip library, CI build) | not started — only if `/safety-scanner/` numbers justify it | — |

Verified live on 2026-11-15: all 6 pages, `/og.png` (1200×630 PNG, Thai text renders) and `/sitemap.xml` return 200;
the ownership meta is on `/`.

## Short rules for other sessions

- **Do not remove** `<meta name="google-site-verification" …>` from `site/index.html` or `site/en/index.html`.
  Search Console drops ownership if it disappears.
- Site copy, README text, repo metadata and images are public text: the owner approves every change (org `AGENTS.md` §6).
  Claims must match what the repo ships — only `fivem-devkit` 0.1.2 and `nakara_cargen_fix` 1.0.0 have releases; unreleased
  pieces are shown as "กำลังพัฒนา · ยังไม่มี release". No "verified by" or vouching badges.
- No binaries in `site/` (hard rule 4). `og.png` is not committed: `pages.yml` renders `docs/assets/og.svg` with
  `rsvg-convert` + `fonts-noto-core` at deploy. Edit the SVG, not a PNG.
- `pages.yml` fills `{{devkit.version}}`, `{{cargen.version}}` and `{{site.date}}` at deploy. Keep the tokens in the HTML.
- A new page needs: `<link rel="canonical">`, `hreflang` th/en/x-default pair, an entry in `site/sitemap.xml`, and a
  link from the landing page. Check at 375 px width for horizontal overflow (long tokens need `overflow-wrap:anywhere`).
- Pages deploys from `main` only (environment `github-pages`, build type `workflow`). A merge to `main` is a public deploy.
- The repo social preview is uploaded by hand in Settings → Social preview (no API). If `og.svg` changes, re-upload the
  new `/og.png` there too.

## Owner's open items

- W3 measurement around 2026-12-13 and the decision on the in-browser scanner.

## Way back

- Site: revert the merge commit on `main` (`git revert f85d1af`, `d102591`, `6a46ecc` in that order) via a PR;
  Pages redeploys from `main`. To take the site down entirely: Settings → Pages → disable.
- Repo metadata: `gh repo edit aeterna/nakara-oss --description … --homepage … --remove-topic …`.
- Search Console: remove the property in the `fivem.tanakon.dev` account (no effect on the site).

## Log

1. 2026-11-15 · plan with Q1–Q6 answered "as recommended" by the owner; scrutiny pass removed overclaims.
2. 2026-11-15 · W1 merged (#46): README pair, Trust Architecture SVGs, Pages site, `pages.yml`; Pages turned on.
3. 2026-11-15 · owner rejected the first site look; mockup approved (D1–D4); redesign merged (#47).
4. 2026-11-15 · W2 built in #48; owner passed page copy, metadata and Search Console plan; OG image redrawn in the
   style of aeterna-rongroi's Forensic Architecture diagram after round 1 was rejected, round 2 passed; merged.
5. 2026-11-15 · repo metadata set; Search Console verified and sitemap submitted (fivem account); owner uploaded the
   social preview.
