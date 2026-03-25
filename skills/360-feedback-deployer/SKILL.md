---
name: 360-feedback-deployer
description: >
  Context and approach skill for the iHasco 360° anonymous feedback system. Use this skill
  whenever continuing work on the 360 feedback form, its deployment pipeline, its Power Automate
  integration, or the Excel results dashboard. Also use it when asked to update colleague lists,
  rotate the webhook URL, add new competencies, change the form's appearance, debug submission
  failures, or extend the GitHub Actions workflow. This skill captures hard-won architectural
  decisions and gotchas from the original build so a new Claude instance doesn't repeat mistakes
  or lose context.
---

# 360° Feedback Deployer — Context Skill

This skill carries the institutional memory of the iHasco anonymous 360° feedback system.
Read it in full before making any changes to any part of the system.

---

## CRITICAL: Always keep these files in sync

Whenever you make a change to this system, check whether **every file in this table** needs updating before closing the task. Do not commit and PR without verifying each one.

| File | Update when… |
|---|---|
| `README.md` | Any change to how the system works, how links are shared, how to set up Power Automate, or what URLs are generated. Always update relevant sections and the troubleshooting table. |
| `power_automate_payload_reference.json` | Any field is added, removed, or renamed in the JSON payload sent by `submitFeedback()` in `src/form-template.html`. The reference must always exactly match what the form sends. |
| `skills/360-feedback-deployer/SKILL.md` | Any architectural change, new gotcha discovered, new file added, or change to how colleague names / tokens / payloads work. Keep this file current so future sessions have accurate context. |
| `src/form-template.html` | Any change to questions, competencies, payload fields, or URL parameter handling. |
| `.github/workflows/deploy.yml` | Any new `src/` file that should be included in the deployment, or changes to the URL structure. |
| `360_feedback_dashboard.xlsx` | New competency columns added or payload fields changed that need a matching column in the `FeedbackResponses` table. **You created this file and can update it directly using `openpyxl` via Bash.** Install with `pip3 install openpyxl` if needed. Always insert columns in the correct position, update the `FeedbackResponses` table ref to match, and copy cell styles from an adjacent header cell. |

**Treat these files as a set.** A change to one nearly always implies a change to at least one other.

---

## What this system is

An anonymous 360° feedback form for iHasco staff. Key properties:

- **Fully anonymous** — no reviewer identity is ever captured or stored
- **No names in source** — colleague names are encoded into a URL token (`?id=`) at link-generation time, never stored in the HTML or repo
- **Public hosting, private data** — the form lives on GitHub Pages (public), responses land in an Excel file in the iHasco O365 environment (private) via Power Automate
- **Unguessable URL** — the live form is deployed to a path derived from `sha256(webhook_url)[:16]`, so the URL cannot be guessed from the public repo
- **No indexing** — the form HTML carries `noindex, nofollow, noarchive` meta tags

---

## Repository structure

```
repo/
├── src/
│   ├── form-template.html          ← The feedback form. Edit this for UI/content changes.
│   │                                  Contains __WEBHOOK_URL__ placeholder — never a real URL.
│   ├── generate.html               ← Link generator form. HR admins use this to create ?id= links.
│   └── expired.html                ← Error page shown when a feedback link token is past its lifetime.
├── .github/
│   └── workflows/
│       └── deploy.yml              ← Injects webhook URL, generates hash path, deploys to gh-pages.
│                                      Also copies generate.html and expired.html into dist.
├── power_automate_payload_reference.json   ← Sample payload JSON. Must stay in sync with submitFeedback().
├── 360_feedback_dashboard.xlsx     ← Upload once to SharePoint/OneDrive. Power Automate writes here.
├── skills/
│   └── 360-feedback-deployer/
│       └── SKILL.md                ← This file
├── .gitignore                      ← Excludes /dist
└── README.md                       ← End-to-end human setup instructions
```

---

## How the deployment pipeline works

```
main branch (src/form-template.html + src/generate.html + src/expired.html)
        │
        ▼
GitHub Actions (deploy.yml)
  1. Reads PA_WEBHOOK_URL from GitHub Actions secret
  2. Computes HASH = sha256(PA_WEBHOOK_URL)[:16]
  3. Injects __WEBHOOK_URL__ → real URL in form-template.html
  4. Writes output to dist/{HASH}/index.html
  5. Copies generate.html  → dist/{HASH}/generate/index.html
  6. Copies expired.html   → dist/expired.html
  7. Writes a blank decoy  → dist/index.html (root shows nothing useful)
  8. Deploys dist/ to gh-pages branch using peaceiris/actions-gh-pages@v4
  9. Prints Generator URL and form base URL to Actions log
        │
        ▼
Generator: https://{owner}.github.io/{repo}/{HASH}/generate/
Form:      https://{owner}.github.io/{repo}/{HASH}/?id=<token>
Expired:   https://{owner}.github.io/{repo}/expired.html
```

Triggers: push to `main` OR manual `workflow_dispatch`.

`keep_files: true` in the deploy step preserves old hashed paths — important if the webhook URL is ever rotated.

---

## How colleague names and link lifetime work

Names and link lifetime are **never** in the repo source. They are encoded by the Generator (`/generate/`) into a URL-safe Base64 token:

```json
{ "n": ["Alice Smith", "Bob Jones"], "c": 1742900000000, "l": 14 }
```

- `n` — array of names
- `c` — creation timestamp (ms since epoch, set at generation time)
- `l` — lifetime in days (7, 14, or 30)

Encoded as: `btoa(JSON.stringify(payload)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=/g,'')`

The token is appended to the form URL: `?id=<token>`

The form's `populateColleaguesFromURL()` decodes the token on page load, checks whether `(Date.now() - c) / 86400000 > l`, and redirects to `../expired.html` if the link has expired. If the token is absent or malformed, the dropdown shows an invalid-link message.

**When updating colleague lists:** generate a new link from `/generate/`. No redeploy needed.

---

## How submissions reach Excel

The form POSTs JSON to the Power Automate webhook URL. The flow has three steps:

1. **When an HTTP request is received** — HTTP trigger, generates the webhook URL
2. **Parse JSON** — validates the payload shape
3. **Add a row into a table** — writes to the `FeedbackResponses` table in `360_feedback_dashboard.xlsx`

The fetch uses standard `fetch()` with `Content-Type: application/json`. **Do not add `mode: 'no-cors'`** — this was tried and removed because it prevents the `Content-Type` header from being sent, which breaks the Power Automate Parse JSON step.

**The Excel table is named `FeedbackResponses`.** Column names must match exactly what the flow expects. Do not rename columns or the table without also updating the Power Automate flow's Add Row action.

---

## Payload schema

The form POSTs this JSON structure (must match `power_automate_payload_reference.json` exactly):

```json
{
  "subject_name": "Alice Smith",
  "form_id": "eyJuIjpbIkFsaWNlIFNtaXRoIl0sImMiOjE3NDI5MDAwMDAwMDAsImwiOjE0fQ",
  "strengths": "Free text...",
  "development": "Free text...",
  "future_focused": 4,
  "adaptability": null,
  "positive_outlook": 3,
  "communication": 5,
  "empathy": null,
  "teamwork": 4,
  "stakeholder_management": 2,
  "planning": 5,
  "inspirational_leadership": 3
}
```

- `form_id` — the raw `?id=` token from the URL; all submissions from the same shared link carry the same value, enabling filtering by session in Excel
- Numeric scores are integers 1–5
- `null` means the competency was marked N/A or skipped; null fields are omitted from the payload

---

## Competency structure

Nine competencies grouped into four pillars:

| Pillar | Competencies |
|---|---|
| Make it Happen | future_focused, adaptability, positive_outlook |
| Never Settle | communication, empathy |
| Choose Right | teamwork, stakeholder_management |
| Smart with Heart | planning (Planning & Problem Solving), inspirational_leadership |

Each competency has a `key` (used in payload), `name` (displayed), and `desc` (behavioural description shown on the card).

To add/remove competencies: edit the `SECTIONS` array in `src/form-template.html`. Also update the Power Automate flow's JSON schema and Add Row column mappings, and add the corresponding column to the `FeedbackResponses` table in Excel. Update `power_automate_payload_reference.json` and `README.md`.

---

## Security model — be honest about this

The security is **obscurity-based**, not cryptographic:

| What is protected | How |
|---|---|
| Webhook URL not in repo source | Stored as GitHub Actions secret, injected at build time only |
| Live URL not guessable from repo | SHA256 hash of webhook URL used as path |
| Colleague names not in source | Encoded in URL token only, never stored |
| Link expiry | Enforced client-side via timestamp in the `?id=` token |
| Search engine discovery | noindex/nofollow/noarchive meta tags |
| Reviewer identity | Never collected — no auth, no identifying cookies |

| What is NOT protected | Why |
|---|---|
| Webhook URL visible in page source | Anyone with the live URL can view-source and find it |
| Webhook abuse by someone with the URL | The URL is the only token — Power Automate has no IP filtering |
| Spam submissions | No CAPTCHA, no rate limiting at form level |
| Token tampering | Base64 encoding is reversible; a determined user could forge a token |

**Mitigation:** The hashed URL is sufficiently obscure in practice. If abuse occurs, regenerate the webhook URL, update the secret, redeploy.

**What was tried and rejected:** A `SUBMIT_SECRET` constant in the JS was briefly added but removed because it is visible in page source alongside the webhook URL — no additional security. Do not re-add it.

---

## SharePoint hosting — why it was rejected

The form was originally intended to be hosted on SharePoint. This was abandoned because:

1. SharePoint's Embed web part only accepts `<iframe>` tags, not raw HTML
2. Uploading the HTML file to a document library and iframing it triggers SharePoint's `X-Frame-Options` headers, which block the iframe
3. Even when the file opens, SharePoint wraps it in the O365 chrome, which breaks `onchange` JavaScript events (the colleague dropdown stopped firing)

**GitHub Pages is the correct hosting solution.** Do not attempt to revisit SharePoint hosting.

---

## Deduplication

The form uses a browser cookie to prevent the same device submitting feedback for the same person twice within 30 days (`DEDUP_DAYS = 30`). Cookie key format: `360fb_{subject_name_lowercased_underscored}`.

This is client-side only — it can be bypassed by clearing cookies or using a different browser. It is a UX safeguard, not a security control.

---

## Known gotchas

- **Do not add `mode: 'no-cors'` to the fetch call.** It prevents `Content-Type: application/json` from being sent, which breaks Power Automate's Parse JSON step. Removed once already — do not re-add.
- **The flow must be turned ON.** After creation, Power Automate flows are off by default. Most common setup mistake.
- **The Excel file must be uploaded before the flow is configured.** The Add Row action browses to the file — it can't target a file that doesn't exist yet.
- **Table name is `FeedbackResponses`.** Power Automate's Add Row action targets named tables, not sheets.
- **`keep_files: true` in deploy.yml is important.** Without it, every redeploy wipes all previously hashed paths.
- **The hash is stable until the secret changes.** A new Generator link only needs to be shared if the webhook URL is rotated or colleague names change.
- **Google Fonts are loaded from CDN.** The form requires internet access to render correctly.
- **Expired redirect path is `../expired.html`** (relative). This works because the form lives at `/{HASH}/` and `expired.html` is deployed at the root of the Pages site.

---

## How to make common changes

### Change or add a competency
Edit `SECTIONS` array in `src/form-template.html`. Update `power_automate_payload_reference.json`. Update PA flow JSON schema and Add Row mappings. Add column to Excel table. Update `README.md` column mapping table. Push to main.

### Update the list of colleagues who can be reviewed
No code change or redeploy needed. Open the Generator (`/{HASH}/generate/`), enter the new names, generate a new link, and share it.

### Rotate the webhook URL
1. In Power Automate: delete the HTTP trigger step, re-add it, save → copies new URL
2. Update `PA_WEBHOOK_URL` secret in GitHub repo settings
3. Push any change to main (or trigger manually)
4. Share new Generator URL from Actions log

### Change the form's visual design
Edit CSS variables in `:root` block in `src/form-template.html`. Core palette uses `--accent: #4F46E5` (indigo). Push to main.

### Add a new open-text question
Add a `<textarea>` to `#screen-open` in the HTML. Capture its value in `submitFeedback()`. Add the field to `power_automate_payload_reference.json`. Update PA flow schema and Add Row action. Add column to Excel. Update `README.md`.

### Debug missing submissions
1. Check Power Automate run history — every POST is logged there
2. Confirm the flow is turned on
3. Check the Excel file path in the Add Row action matches where the file actually lives
4. Check the table is named `FeedbackResponses`
