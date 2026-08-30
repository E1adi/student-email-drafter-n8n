# Student Email Drafter — n8n Workflow

Automatically drafts Gmail review emails for student project submissions. Give it a folder of assignment files and a class roster — it extracts student names and the paper title (via Gemini), looks up the supervisor's email from the roster, attaches the matching review file, and saves a ready-to-send Gmail draft **per paper** addressed to the supervisor.

---

## How it works

```
Trigger → Clear cache → List assignments → Split (one item per file)
  → Extract names + title (Gemini)
  → Match supervisor email from roster
  → Find review file
  → Fetch template → Build email → Render MD → Attach review → Save Gmail draft
```

One draft per assignment file. The supervisor is the recipient. All student names from the paper appear in the email body.

---

## Prerequisites

- Docker + Docker Compose
- A Google Cloud project with the Gmail API enabled
- A Gemini API key (free tier via [Google AI Studio](https://aistudio.google.com))

---

## Setup

### 1. Clone and run the installer

```bash
git clone https://github.com/E1adi/student-email-drafter-n8n.git
cd student-email-drafter-n8n
bash install.sh
```

The installer checks for Homebrew, git, and Docker, creates `.env` from `.env.example`, scaffolds `files/`, copies the email template, and starts the stack.

### 2. Edit `.env`

```env
# Gemini (free tier) — get key at https://aistudio.google.com/app/apikey
LLM_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/
LLM_API_KEY=your_gemini_api_key_here
LLM_MODEL=gemini-2.0-flash

# n8n encryption key — any random string
N8N_ENCRYPTION_KEY=any_random_string_here

# Extractor sidecar port (must match docker-compose.yml and all workflow HTTP Request nodes)
EXTRACTOR_PORT=5050
```

Re-run `bash install.sh` after editing — it validates your key and warns on port mismatches.

### 3. Add your files

```
files/
├── assignments/           ← student submission PDFs/DOCXs
├── reviews/               ← your review DOCXs (named so the student name is findable)
├── roster.xlsx            ← class roster (see format below)
└── email_template.md      ← email template (copied from email_template.example.md)
```

**Roster format** — required columns (extra columns ignored, multiple students per row supported):

| Student Name 1 | Student Email 1 | Student Name 2 | Student Email 2 | Supervisor | Supervisor Email |
|---|---|---|---|---|---|
| Sharon Raz | sharon@uni.ac.il | Guy Abitbol | guy@uni.ac.il | Dr. Smith | smith@uni.ac.il |

The workflow uses student names to locate the correct roster row, then reads the **Supervisor** and **Supervisor Email** columns for the draft.

**Email template format** (`files/email_template.md`):

```markdown
Subject: Final Project Review - {{full_name}}

Dear Prof. {{supervisor}},

...body with **bold** and [links](https://...) ...

Best regards,  
Yael
```

The first line must be `Subject: ...` followed by a blank line. Available placeholders:

| Placeholder | Value |
|---|---|
| `{{full_name}}` | All student names joined with `&` |
| `{{name}}` | First student's first name |
| `{{paper_title}}` | Paper title extracted from the PDF |
| `{{supervisor}}` | Supervisor name from the roster |

Markdown formatting is converted to HTML before sending — `**bold**` renders as bold, `[text](url)` renders as a clickable link.

### 4. Configure Gmail OAuth2

You need a Google Cloud project with the Gmail API enabled. Do this once:

**A. Enable the Gmail API**
1. Go to [Google Cloud Console](https://console.cloud.google.com) → select or create a project
2. Go to **APIs & Services → Library**
3. Search for **Gmail API** → click it → **Enable**

**B. Configure the OAuth consent screen**
1. Go to **APIs & Services → OAuth consent screen**
2. Choose **External** → **Create**
3. Fill in App name (e.g. `n8n Email Drafter`), your email as support + developer contact → **Save and Continue**
4. Scopes page → **Save and Continue** (no scopes needed here)
5. Test users → **Add users** → add your Gmail address → **Save and Continue**

**C. Create OAuth2 credentials**
1. Go to **APIs & Services → Credentials → Create Credentials → OAuth client ID**
2. Application type: **Web application**
3. Under **Authorized redirect URIs** add: `http://localhost:5678/rest/oauth2-credential/callback`
4. Click **Create** → note the **Client ID** and **Client Secret**

**D. Add the credential in n8n**
1. Open **http://localhost:5678 → Settings → Credentials → New**
2. Search for **Gmail OAuth2 API**
3. Paste Client ID and Client Secret
4. Click **Sign in with Google** and authorize with your Gmail account
5. Save as e.g. `Gmail`

### 5. Import the workflow

1. In n8n, go to **Workflows → Import from file**
2. Select `workflow.json`
3. Open the **Create Gmail Draft** node → set its credential to the `Gmail` credential you just created
4. Save the workflow

### 6. Run

Click **Test workflow**. Check Gmail Drafts — one draft per assignment file, addressed to the supervisor.

---

## Architecture

| Component | Role |
|---|---|
| `n8n` | Workflow orchestration (port 5678) |
| `extractor` (Python/Flask) | File parsing, LLM calls, roster matching, file serving (port `EXTRACTOR_PORT`) |
| `files/` volume | Shared between host and both containers |

The extractor exposes these endpoints:

| Endpoint | What it does |
|---|---|
| `POST /clear-cache` | Clears in-memory roster + template cache (called automatically at workflow start) |
| `GET /list-assignments` | Lists files in `assignments/` |
| `POST /extract-name` | Extracts student names + paper title from a PDF/DOCX via Gemini |
| `POST /match-roster` | Fuzzy-matches student names to roster rows; returns supervisor name + email |
| `POST /find-review` | Fuzzy-matches a student name to a review file |
| `GET /get-template` | Returns the email template (`email_template.md`, cached in memory) |
| `GET /download-review?path=...` | Serves a review file as binary |

---

## Switching LLM providers

Only `extract-name` uses an LLM. Change these three `.env` variables:

| Provider | `LLM_BASE_URL` | `LLM_MODEL` |
|---|---|---|
| Gemini (free) | `https://generativelanguage.googleapis.com/v1beta/openai/` | `models/gemini-3.5-flash-lite` |
| OpenAI | *(leave blank)* | `gpt-4o-mini` |
| Local (Ollama) | `http://host.docker.internal:11434/v1` | `llama3.2` |

Restart the extractor after changing: `docker compose up -d --build extractor`

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Draft sent to student instead of supervisor | Check roster has `Supervisor Email` column with correct header |
| `No roster match` error | Check that roster column headers are `Student Name 1` / `Student Email 1` |
| Review file not found | Ensure the student's name appears somewhere in the review filename |
| Gmail credential error | Re-authorize the OAuth2 credential in n8n Settings |
| Template subject appears in body | First line of template must be `Subject: ...` followed by a **blank line** |
| Bold/links not rendering | Make sure `emailType` is set to `html` in the Create Gmail Draft node |
| Cache stale after swapping roster | The Clear Cache node runs automatically on each workflow trigger |
