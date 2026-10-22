# Build Plan: the Strata Website

Read [intent.md](intent.md) for what we're building and [spec.md](spec.md) for how; this file covers **the order we do it in**.

**How to use this plan**
- Work through the phases in order. Each phase ends with a **✅ Done when** checklist; don't start the next one until every box is ticked.
- `§` references point to sections in spec.md.
- Commit to git at the end of every phase.

---

## Phase 0: Scaffold

**Goal:** an empty Vite + React + TypeScript app with Tailwind working.

1. `npm create vite@latest frontend -- --template react-ts` from the repo root.
2. `npm install -D tailwindcss @tailwindcss/vite`; add `tailwindcss()` to `vite.config.ts` and set `base: './'` (§8).
3. Replace `src/index.css` with `@import "tailwindcss";` plus the `@theme` tokens (§6). Delete the template's demo assets and `App.css`.
4. Export `public/icon.png` and `public/favicon.png` from `Resources/AppIcon.icns` (§7).
5. `index.html`: real `<title>`, meta description, Open Graph tags, favicon.

✅ **Done when**
- [x] `npm run dev` shows a white page styled with Tailwind classes
- [x] `npm run build` succeeds

---

## Phase 1: Hero and download button

**Goal:** someone landing on the page can download the newest Strata in one click.

1. `release.ts`: `useLatestRelease()` with the API lookup, asset matching, sessionStorage cache and fallback (§5).
2. `DownloadButton` component: fallback `href` first, swapped to the asset URL once loaded; the meta line under it.
3. `Header` with icon, name, anchor links and a small download button.
4. `Hero`: headline, pitch, DownloadButton, and the mock taskbar (§4.1).

✅ **Done when**
- [x] The button downloads `Strata-<latest>.zip` directly
- [x] With `api.github.com` blocked, the button opens the releases page instead
- [x] The meta line shows the real version and size

---

## Phase 2: Content sections

**Goal:** all the information from the README, laid out for non-technical readers.

1. `Features`: six cards with small inline SVG icons.
2. `Install`: three numbered steps, with the **Open Anyway** path spelled out.
3. `Shortcuts`: the ⌃⌥ table with keycap styling.
4. `Faq`: `<details>` items.
5. Final call to action and `Footer`.

✅ **Done when**
- [x] Every section in the §4 table is on the page, in order
- [x] Copy matches the root README (features, install steps, shortcuts)
- [x] Header anchor links scroll to the right sections

---

## Phase 3: Polish

**Goal:** it looks and behaves well everywhere.

1. Responsive pass at 375 / 768 / 1440 px.
2. Accessibility pass: landmarks, focus rings, keycap labels, contrast (§6).
3. `prefers-reduced-motion`: turn off smooth scrolling and hover transitions.
4. `npm run lint` clean.

✅ **Done when**
- [ ] Every box in the §9 checklist is ticked (needs a person with a browser and a phone)

---

## Phase 4: Deploy to GitHub Pages

**Goal:** the site is live and redeploys itself.

1. Add `.github/workflows/pages.yml` (§8).
2. In the repo on GitHub: **Settings → Pages → Source: GitHub Actions**.
3. Push to `main` and watch the workflow run.
4. Link the site from the root `README.md` and the GitHub repo's "Website" field.

✅ **Done when**
- [ ] `https://takshittt.github.io/strata-taskbar/` loads and the download works
- [ ] A push that changes `frontend/` redeploys automatically
- [ ] A push that changes only the Swift app doesn't trigger a deploy
