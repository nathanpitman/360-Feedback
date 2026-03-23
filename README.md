# 360° Feedback Form

Anonymous 360° feedback tool for iHasco. Responses are written directly to an Excel file in your O365 environment via Power Automate. Colleague names are never stored in this repo — they're passed as a URL parameter at link-share time. The form is deployed to an unguessable hashed URL on GitHub Pages.

---

## How it works

```
You share a link:
  https://you.github.io/360-feedback/{hash}/?colleagues=Alice,Bob

       ↓  (names only exist in the link, never in source)

Colleague fills in the form on GitHub Pages

       ↓  (POST to Power Automate webhook — URL injected at build time, not in repo)

Power Automate writes a row to 360_feedback_dashboard.xlsx in your SharePoint/OneDrive
```

The `{hash}` in the URL is derived from your Power Automate webhook URL at build time — unguessable from the outside, but stable unless you rotate the secret.

---

## Files in this repo

| File | Purpose |
|---|---|
| `src/form-template.html` | The feedback form. Edit this to change questions or styling. Contains no secrets. |
| `power_automate_payload_reference.json` | Sample JSON payload. Paste into Power Automate's "Generate from sample" when building the flow. |
| `360_feedback_dashboard.xlsx` | Excel template. Upload once to SharePoint or OneDrive. Responses write here. |
| `.github/workflows/deploy.yml` | Build and deploy pipeline. Injects the webhook URL and publishes to GitHub Pages. |
| `skills/360-feedback-deployer/SKILL.md` | Context skill for AI assistants continuing work on this project. |

---

## One-time setup

### Step 1 — Upload the Excel template to SharePoint or OneDrive

1. Upload `360_feedback_dashboard.xlsx` to a SharePoint document library or your OneDrive
2. Note the **site/drive path** — you'll need it in Step 2
3. Make sure the file stays at this location permanently — Power Automate will write to it by path

> The file contains a table named `FeedbackResponses`. Do not rename this table or its columns or the Power Automate flow will break.

---

### Step 2 — Build the Power Automate flow

> **Note:** Power Automate's Import Package requires a proprietary zip format. The flow must be built manually — it only takes about 5 minutes and has 3 steps.

**2a. Create a new flow**

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. **My Flows → + New flow → Instant cloud flow**
3. Name it `360 Feedback Receiver`
4. Choose trigger: **When an HTTP request is received** → Create

**2b. Add a Parse JSON step**

1. Click **+ New step** → search for `Parse JSON` → select it
2. Set **Content** to `Body` from the trigger's dynamic content panel
3. Click **Generate from sample** and paste the entire contents of `power_automate_payload_reference.json` from this repo
4. Click Done — Power Automate will generate the schema automatically

**2c. Add an Excel — Add a row into a table step**

1. Click **+ New step** → search `Excel Online (Business)` → select **Add a row into a table**
2. Fill in the fields:
   - **Location**: select your SharePoint site or OneDrive
   - **Document Library**: the library where you uploaded the Excel file
   - **File**: browse to `360_feedback_dashboard.xlsx`
   - **Table**: select `FeedbackResponses`
3. Map each column to the matching field from the Parse JSON dynamic content:

| Excel column | Dynamic content value |
|---|---|
| Timestamp | Use expression: `utcNow()` |
| Subject Name | `subject_name` |
| Future Focused | `future_focused` |
| Adaptability | `adaptability` |
| Positive Outlook | `positive_outlook` |
| Communication | `communication` |
| Empathy | `empathy` |
| Teamwork | `teamwork` |
| Stakeholder Management | `stakeholder_management` |
| Planning & Problem Solving | `planning` |
| Inspirational Leadership | `inspirational_leadership` |
| Strengths | `strengths` |
| Development Areas | `development` |

**2d. Save and get your webhook URL**

1. Click **Save**
2. Go back to the **When an HTTP request is received** trigger step
3. Copy the **HTTP POST URL** — this is your `PA_WEBHOOK_URL`
4. Make sure the flow is **turned on** (flows default to off after creation)

> Keep this URL private. It is the only security layer between the public internet and your Excel file.

---

### Step 3 — Add the webhook URL as a GitHub secret

1. In this repo, go to **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Set:
   - **Name**: `PA_WEBHOOK_URL`
   - **Value**: the full webhook URL from Step 2

---

### Step 4 — Enable GitHub Pages

1. Go to **Settings → Pages**
2. Set **Source** to: `Deploy from a branch`
3. Set **Branch** to: `gh-pages` / `/ (root)`
4. Save

> The `gh-pages` branch is created automatically on first deploy.

---

### Step 5 — Deploy

Either push any change to `main`, or go to:

**Actions → Deploy 360 Feedback Form → Run workflow → Run workflow**

Once complete, check the Actions log for your live URL:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Live form URL:
https://yourusername.github.io/360-feedback/a3f7c2d1e4b89f01/
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Sharing the form

Add colleague names as a comma-separated `colleagues` URL parameter. Spaces become `%20`.

**Example:**
```
https://yourusername.github.io/360-feedback/a3f7c2d1e4b89f01/?colleagues=Alice%20Smith,Bob%20Jones,Carol%20Lee
```

Anyone visiting the link without a `colleagues` parameter will see a message telling them to contact their HR admin.

**Tip:** Build a simple link-generator spreadsheet in Excel — one column of names, a formula to join them with commas, and a HYPERLINK() to assemble the full URL.

---

## Updating the form

Edit `src/form-template.html` and push to `main`. The workflow redeploys automatically within ~1 minute.

---

## Rotating the webhook URL

If you ever need to invalidate the current URL (e.g. suspected abuse):

1. In Power Automate, delete the HTTP trigger and re-add it — this generates a new URL
2. Update the `PA_WEBHOOK_URL` secret in GitHub
3. Push any change to `main` to trigger a redeploy
4. The hashed path in the URL will change — share the new link

Old links will 404 automatically.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Submissions don't appear in Excel | Flow is turned off | Go to Power Automate and turn the flow on |
| Submissions don't appear in Excel | Excel table name changed | Ensure the table is named `FeedbackResponses` |
| Submissions don't appear in Excel | Wrong file path in flow | Re-check the Drive and File fields in the Add Row action |
| GitHub Pages shows 404 | Pages not configured | Check Settings → Pages → gh-pages branch |
| Actions log shows secret not set | Secret missing | Add `PA_WEBHOOK_URL` in Settings → Secrets → Actions |
| Dropdown shows "No colleagues in link" | URL parameter missing | Ensure `?colleagues=Name1,Name2` is appended to the URL |
