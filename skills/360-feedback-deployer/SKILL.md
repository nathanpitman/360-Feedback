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

## What this system is

An anonymous 360° feedback form for iHasco staff. Key properties:

- **Fully anonymous** — no reviewer identity is ever captured or stored
- **No names in source** — colleague names are passed as URL parameters at share time, not stored in the HTML or repo
- **Public hosting, private data** — the form lives on GitHub Pages (public), responses land in an Excel file in the iHasco O365 environment (private) via Power Automate
- **Unguessable URL** — the live form is deployed to a path derived from `sha256(webhook_url)[:16]`, so the URL cannot be guessed from the public repo
- **No indexing** — the form HTML carries `noindex, nofollow, noarchive` meta tags

---

## Repository structure

```
repo/
├── src/
│   └── form-template.html          ← The form. Edit this for UI/content changes.
│                                      Contains __WEBHOOK_URL__ placeholder — never a real URL.
├── .github/
│   └── workflows/
│       └── deploy.yml              ← Injects webhook URL, generates hash path, deploys to gh-pages
├── power_automate_payload_reference.json        ← Sample payload JSON. Paste into PA "Generate from sample" when building the flow manually.
├── 360_feedback_dashboard_v2.xlsx  ← Upload once to SharePoint/OneDrive. Power Automate writes here.
├── skills/
│   └── 360-feedback-deployer/
│       └── SKILL.md                ← This file
├── .gitignore                      ← Excludes /dist
└── README.md                       ← End-to-end human setup instructions
```

---

## How the deployment pipeline works

```
main branch (src/form-template.html)
        │
        ▼
GitHub Actions (deploy.yml)
  1. Reads PA_WEBHOOK_URL from GitHub Actions secret
  2. Computes HASH = sha256(PA_WEBHOOK_URL)[:16]
  3. sed-substitutes __WEBHOOK_URL__ → real URL in the HTML
  4. Writes output to dist/{HASH}/index.html
  5. Writes a blank decoy to dist/index.html (root shows nothing useful)
  6. Deploys dist/ to gh-pages branch using peaceiris/actions-gh-pages@v4
  7. Prints live URL to Actions log
        │
        ▼
Live URL: https://{owner}.github.io/{repo}/{HASH}/
Share as: https://{owner}.github.io/{repo}/{HASH}/?colleagues=Name1,Name2
```

Triggers: push to `main` OR manual `workflow_dispatch`.

`keep_files: true` in the deploy step preserves old hashed paths — important if the webhook URL is ever rotated, old links break gracefully rather than wiping everything.

---

## How colleague names work

Names are **never** in the repo source. They are passed as a URL query parameter:

```
?colleagues=Alice%20Smith,Bob%20Jones,Carol%20Lee
```

The form's `populateColleaguesFromURL()` function reads `URLSearchParams`, splits on commas, and builds `<option>` elements dynamically on page load.

If the parameter is absent, the dropdown shows:
> "— No colleagues in link. Contact your HR admin. —"

**When updating colleague lists:** you do not touch the HTML or redeploy. You simply share a new link with a different `?colleagues=` parameter. This is intentional — it means the form can be used for any cohort without a redeploy.

**Encoding:** spaces → `%20`, commas separate names. Standard `encodeURIComponent` on each name then join with `,`.

---

## How submissions reach Excel

The form POSTs JSON to the Power Automate webhook URL. The flow has three steps:

1. **When an HTTP request is received** — HTTP trigger, generates the webhook URL
2. **Parse JSON** — validates the payload shape
3. **Add a row into a table** — writes to the `FeedbackResponses` table in `360_feedback_dashboard_v2.xlsx`

The fetch uses `mode: 'no-cors'` because Power Automate does not return CORS headers. This means the form cannot read the response — it optimistically shows the thank-you screen regardless. Failed submissions (e.g. flow turned off) are silent to the user. Check Power Automate run history to diagnose.

**The Excel table is named `FeedbackResponses`.** Column names must match exactly what the flow expects. Do not rename columns or the table without also updating the Power Automate flow's Add Row action.

---

## Payload schema

The form POSTs this JSON structure:

```json
{
  "subject_name": "Alice Smith",
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

- Numeric scores are integers 1–5
- `null` means the competency was marked N/A or skipped
- `reviewer_relationship` is defined in the PA flow schema but not currently collected by the form — it will arrive as `undefined`/absent

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

To add/remove competencies: edit the `SECTIONS` array in `src/form-template.html`. Also update the Power Automate flow's JSON schema and Add Row column mappings, and add the corresponding column to the `FeedbackResponses` table in Excel.

---

## Security model — be honest about this

The security is **obscurity-based**, not cryptographic. Be clear about this with stakeholders:

| What is protected | How |
|---|---|
| Webhook URL not in repo source | Stored as GitHub Actions secret, injected at build time only |
| Live URL not guessable from repo | SHA256 hash of webhook URL used as path |
| Colleague names not in source | URL parameter only, never stored |
| Search engine discovery | noindex/nofollow/noarchive meta tags |
| Reviewer identity | Never collected — no auth, no cookies that identify the person |

| What is NOT protected | Why |
|---|---|
| Webhook URL visible in page source | Anyone with the live URL can view-source and find it |
| Webhook abuse by someone with the URL | The URL is the only token — Power Automate has no IP filtering |
| Spam submissions | No CAPTCHA, no rate limiting at form level |

**Mitigation already in place:** The hashed URL is sufficiently obscure in practice. Power Automate run history provides an audit trail. If abuse occurs, regenerate the webhook URL (new trigger in PA), update the GitHub secret, redeploy — old URL instantly dead.

**What was tried and rejected:** A `SUBMIT_SECRET` constant in the JS was briefly added but removed because it is visible in page source alongside the webhook URL — it provides no additional security. Do not re-add it.

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

- **`mode: 'no-cors'` means silent failures.** If Power Automate is turned off or the flow errors, the form still shows the thank-you screen. Always check PA run history when diagnosing missing data.
- **The flow must be turned ON.** After import, Power Automate flows are off by default. This is the most common setup mistake.
- **The Excel file must be uploaded before the flow is configured.** The Add Row action needs to browse to the file — it can't be configured against a file that doesn't exist yet.
- **Table name is `FeedbackResponses`.** Power Automate's Add Row action targets named tables, not sheets. If the table is missing or renamed, the flow will error.
- **`keep_files: true` in deploy.yml is important.** Without it, every redeploy wipes all previously hashed paths. If the webhook is rotated and old paths should 404, set this to `false` temporarily then back to `true`.
- **The hash is stable until the secret changes.** `sha256(webhook_url)[:16]` always produces the same path for the same URL. A new link only needs to be shared if the webhook URL is rotated.
- **Google Fonts are loaded from CDN** (`fonts.googleapis.com`). The form requires internet access to render correctly — it will work but look wrong offline.

---

## How to make common changes

### Change or add a question / competency
Edit `SECTIONS` array in `src/form-template.html`. Update PA flow JSON schema and Add Row mappings. Add column to Excel table. Push to main.

### Update the list of colleagues who can be reviewed
No code change needed. Just share a new URL with updated `?colleagues=` parameter.

### Rotate the webhook URL
1. In Power Automate: delete the HTTP trigger step, re-add it, save → copies new URL
2. Update `PA_WEBHOOK_URL` secret in GitHub repo settings
3. Push any change to main (or trigger manually)
4. Share new URL from Actions log

### Change the form's visual design
Edit CSS variables in `:root` block in `src/form-template.html`. Core palette uses `--accent: #4F46E5` (indigo). Push to main.

### Add a new open-text question
Add a `<textarea>` to `#screen-open` in the HTML. Capture its value in `submitFeedback()`. Add the field to the PA flow schema and Add Row action. Add column to Excel.

### Debug missing submissions
1. Check Power Automate run history — every POST is logged there
2. Confirm the flow is turned on
3. Check the Excel file path in the Add Row action matches where the file actually lives
4. Check the table is named `FeedbackResponses`
