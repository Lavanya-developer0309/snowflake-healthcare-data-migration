# Setup Guide: from zero to your first scorecard

This guide assumes you know SQL well but are new to Snowflake, dbt, Python and GitHub.
Follow the parts in order. Plan for **2–3 hours** the first time.

> Snowsight menus get renamed from time to time. If a menu name below doesn't match what you see,
> look for the closest equivalent (e.g. *Data → Databases* vs *Catalog → Database Explorer*).

---

## Part A — Create a Snowflake trial account (10 min)

1. Go to **https://signup.snowflake.com** and sign up.
2. Choose:
   - **Edition:** Enterprise (needed for masking policies; the trial is free)
   - **Cloud provider:** AWS
   - **Region:** Asia Pacific (Mumbai)
3. Activate the account from the email, set your username and password, and set up **MFA**
   (Snowflake requires it for password sign-in).
4. You get 30 days / $400 of free credits. This project uses well under $10.

---

## Part B — Build the Snowflake objects (20 min)

In Snowsight open **Projects → Workspaces** (or **Worksheets**), create a new SQL file, paste a script,
and click **Run all** (Ctrl + Shift + Enter on Windows, Cmd + Shift + Enter on Mac).

Run these files **in this order**, one at a time:

| # | File | What it creates |
|---|---|---|
| 1 | `sql/00_setup/01_roles_warehouse_database.sql` | roles, warehouse `MIG_WH`, database `HC_MIGRATION_DB`, 10 schemas, grants |
| 2 | `sql/00_setup/02_file_formats_and_stages.sql` | file formats + 3 internal stages |
| 3 | `sql/00_setup/03_control_and_audit_tables.sql` | config, batch control, logs, profiling, scorecard tables |
| 4 | `sql/00_setup/04_masking_policies.sql` | 4 masking policies |
| 5 | `sql/01_raw_load/01_raw_tables.sql` | 5 RAW landing tables |
| 6 | `sql/01_raw_load/02_sp_load_raw.sql` | `SP_LOAD_RAW` |
| 7 | `sql/02_profiling/01_sp_profile_source.sql` | `SP_PROFILE_SOURCE`, `SP_PROFILE_ALL`, `V_DQ_PROFILE_REPORT` |
| 8 | `sql/03_target_load/01_sp_load_facets_target.sql` | `SP_LOAD_FACETS_TARGET` |
| 9 | `sql/04_scorecard/01_sp_build_scorecard.sql` | `SP_BUILD_SCORECARD`, `V_SCORECARD`, `V_ERROR_SUMMARY` |
| 10 | `sql/05_orchestration/01_tasks_dag.sql` | `SP_RUN_STEP` + 4 tasks |

`sql/00_setup/05_dbt_service_user.sql` comes later (Part D), and the `06_*` scripts after the first run.

Check: **Catalog → Database Explorer → HC_MIGRATION_DB** should show all the schemas.

---

## Part C — Upload the source extracts (5 min)

The five files are already generated in `data/source/BATCH_001/`.
(To generate them again: `python scripts/generate_source_data.py`.)

**Option 1 — Snowsight (no install):**
1. Catalog → Database Explorer → `HC_MIGRATION_DB` → `RAW` → **Stages** → `SRC_STAGE`.
2. Click **+ Files**, drag in the 5 `SRC_*.txt` files (not the `.json`).
3. In **"Specify the path"** type `BATCH_001` and upload.

**Option 2 — Snowflake CLI** (`pip install snowflake-cli`):
```bash
snow stage copy "data/source/BATCH_001/*.txt" @HC_MIGRATION_DB.RAW.SRC_STAGE/BATCH_001/
```

Check in a worksheet:
```sql
LIST @HC_MIGRATION_DB.RAW.SRC_STAGE/BATCH_001/;     -- 5 files
```

You can already run the Snowflake-only steps by hand:
```sql
USE ROLE MIG_DEVELOPER; USE WAREHOUSE MIG_WH; USE DATABASE HC_MIGRATION_DB;
CALL AUDIT.SP_LOAD_RAW('BATCH_001');
CALL AUDIT.SP_PROFILE_ALL('BATCH_001');
SELECT TABLE_NAME, COLUMN_NAME, DQ_OBSERVATIONS FROM AUDIT.V_DQ_PROFILE_REPORT
 WHERE BATCH_ID = 'BATCH_001' AND DQ_OBSERVATIONS <> '';
```

---

## Part D — Set up your laptop (30–45 min)

### D1. Install the tools
| Tool | Where | Note |
|---|---|---|
| **Python 3.12** | https://www.python.org/downloads/ | Use **3.12**, not 3.14 / 3.15 (too new for dbt). Windows: tick **"Add python.exe to PATH"** |
| Git | Mac: `xcode-select --install` · Windows: https://git-scm.com/downloads | defaults are fine |
| VS Code | https://code.visualstudio.com | optional extension: *dbt Power User* |

**macOS only — run once after installing Python from python.org** (otherwise downloads fail
with `SSL: CERTIFICATE_VERIFY_FAILED`):
```bash
open "/Applications/Python 3.12/Install Certificates.command"
```

Check in a new terminal (Terminal on Mac, PowerShell on Windows):
```bash
python3.12 --version     # macOS  -> Python 3.12.x
git --version
```
```powershell
py -3.12 --version       # Windows -> Python 3.12.x
git --version
```

> On a Mac the command is `python3` / `python3.12`, **not** `python` (`zsh: command not found: python`
> just means that).

### D2. Python environment + dbt

**1. Open a terminal in the project folder**

- macOS: open Terminal and type
  ```bash
  cd ~/Downloads/Lavanya/snowflake-healthcare-data-migration
  ```
  (or in Finder right-click the project folder → **Services → New Terminal at Folder**)
- Windows: open the project folder in File Explorer, type `powershell` in the address bar, press Enter.

Check you are in the right place — `ls` (Mac) / `dir` (Windows) should list `README.md`, `dbt`, `docs`, `sql` ...

**2. Create the virtual environment with Python 3.12 and install dbt**

```bash
# macOS
python3.12 -m venv .venv
source .venv/bin/activate          # prompt now starts with (.venv)
python --version                   # must show 3.12.x
pip install -r requirements.txt
dbt --version
```
```powershell
# Windows PowerShell
py -3.12 -m venv .venv
.venv\Scripts\activate             # prompt now starts with (.venv)
python --version                   # must show 3.12.x
pip install -r requirements.txt
dbt --version
```

`dbt --version` should show **Core 1.12.x** and **snowflake 1.12.x**. The "dbt v2 is available"
message and the pip upgrade notice can be ignored.

**3. Every time you open a new terminal for this project**
```bash
cd ~/Downloads/Lavanya/snowflake-healthcare-data-migration
source .venv/bin/activate          # Windows: .venv\Scripts\activate
```

**If `pip install` failed** (wrong Python version or SSL error), start the environment again:
```bash
deactivate
rm -rf .venv                       # Windows: Remove-Item -Recurse -Force .venv
# fix the cause (install Python 3.12 / run Install Certificates.command), then repeat step 2
```

> Install dbt with **pip** as shown. dbt's website also offers a newer "dbt Fusion / v2" installer;
> this project is written and tested for dbt Core 1.12.

### D3. Key pair for the dbt service user
Snowflake requires MFA for password logins, which doesn't suit tools like dbt. So dbt signs in as a
service user with a key pair:

```bash
python scripts/generate_keypair.py
```
It saves the keys in `~/.ssh/snowflake/` (outside the project, so they never go to GitHub) and prints an
`ALTER USER MIG_DBT_SVC SET RSA_PUBLIC_KEY = '...';` line.

Open `sql/00_setup/05_dbt_service_user.sql` in Snowsight, replace `PASTE_YOUR_PUBLIC_KEY_HERE` with the
printed key, and **Run all**.

### D4. dbt profile + environment variables
1. Copy `dbt/profiles.yml.example` to:
   - Windows: `C:\Users\<you>\.dbt\profiles.yml` (create the `.dbt` folder)
   - Mac/Linux: `~/.dbt/profiles.yml`
2. Find your **account identifier**: in Snowsight click your name (bottom-left) → **Connect a tool to
   Snowflake** → *Account identifier*, e.g. `ABCDEFG-XY12345`.
3. Set the variables (the `setx` lines make them permanent on Windows; then open a **new** terminal):

```powershell
# Windows
setx SNOWFLAKE_ACCOUNT "ABCDEFG-XY12345"
setx SNOWFLAKE_PRIVATE_KEY_PATH "C:\Users\<you>\.ssh\snowflake\rsa_key.p8"
```
```bash
# macOS / Linux (add to ~/.zshrc or ~/.bashrc to keep them)
export SNOWFLAKE_ACCOUNT="ABCDEFG-XY12345"
export SNOWFLAKE_PRIVATE_KEY_PATH="$HOME/.ssh/snowflake/rsa_key.p8"
```

### D5. Test the connection
```bash
cd dbt
dbt deps        # installs dbt_utils
dbt debug       # must end with "All checks passed!"
```

---

## Part E — Run the pipeline (15 min)

### First time: step by step (so you see each stage)
From the `dbt` folder:

```bash
dbt run-operation load_raw            # 1  SP_LOAD_RAW        -> RAW tables
dbt run-operation profile_source      # 2  SP_PROFILE_ALL     -> profiling + client report
dbt run-operation clear_keyword_files # 3  remove old keyword files
dbt build                             # 4  seeds, models, tests (gate), keyword files
dbt run-operation load_target         # 5  SP_LOAD_FACETS_TARGET -> FACETS_TGT
dbt run-operation build_scorecard     # 6  SP_BUILD_SCORECARD -> scorecard + error log
```

In step 4 you will see some tests marked **WARN**. They are the source data problems the generator injected
(invalid dates, bad SSNs, invalid characters, orphans, bad NPIs, negative paid lines). That's
expected and they don't stop the load. All **ERROR** tests should **PASS**.

### After that: one command
The script lives in the `orchestration` folder, so run it from the **project folder**, not from
inside `dbt`. If you just did the step-by-step run above, go back up one level first:
```bash
cd ..                                               # back to snowflake-healthcare-data-migration
bash orchestration/run_pipeline.sh BATCH_001        # macOS / Linux / Git Bash
```
```powershell
.\orchestration\run_pipeline.ps1 -Batch BATCH_001   # Windows PowerShell
```
(`bash orchestration/...` works even if the file lost its "executable" permission when it was
copied or unzipped. To use `./orchestration/run_pipeline.sh` instead, run
`chmod +x orchestration/run_pipeline.sh` once.)

### Or with Snowflake Tasks
```sql
EXECUTE TASK HC_MIGRATION_DB.AUDIT.T_MIG_PRE_ROOT;     -- load + profile
-- run "dbt build" on your laptop
EXECUTE TASK HC_MIGRATION_DB.AUDIT.T_MIG_POST_ROOT;    -- load target + scorecard
```

---

## Part F — Look at the results

Open `sql/07_queries/01_useful_queries.sql` in Snowsight and run the queries one by one. The most important:

```sql
SELECT * FROM HC_MIGRATION_DB.AUDIT.V_SCORECARD     WHERE BATCH_ID = 'BATCH_001' ORDER BY ENTITY_NAME;
SELECT * FROM HC_MIGRATION_DB.AUDIT.V_ERROR_SUMMARY WHERE BATCH_ID = 'BATCH_001' ORDER BY SEVERITY;
```

**Expected result for the BATCH_001 files in this repo** (generated with `--seed 42`):

| Entity | Source | Rejected | Staged = Keyword = Target | Status |
|---|---:|---:|---:|---|
| GROUP | 60 | 0 | 60 | PASSED (group name defaulted is a source warning) |
| SUBSCRIBER | 1,505 | 9 | 1,496 | PASSED_WITH_WARNINGS |
| MEMBER | 3,938 | 36 | 3,902 | PASSED_WITH_WARNINGS |
| ELIGIBILITY | 3,938 | 36 | 3,902 | PASSED_WITH_WARNINGS |
| PROVIDER | 350 | 3 | 347 | PASSED_WITH_WARNINGS |
| CLAIM | 8,000 | 125 | 7,875 | PASSED_WITH_WARNINGS |
| CLAIM_LINE | 15,962 | 240 | 15,722 | PASSED_WITH_WARNINGS |

`dbt build` should finish with **ERROR=0** and **13 WARN** tests (all expected).

Compare the reject reasons with `data/source/BATCH_001/_injected_issues.json`. Every injected problem
should appear, either as a reject reason, a warning, or a profiling observation. (Counts can differ a
little from the JSON when one record has two problems: a record is rejected for the *first* rule it fails.
Claims and lines also include cascade rejects, e.g. claims of rejected members.)

**Then try the extras:**
1. `sql/06_security_and_recovery/01_apply_masking_to_target.sql`: same query, three roles.
2. `sql/06_security_and_recovery/02_time_travel_and_clone_demo.sql`: undo a bad UPDATE, UNDROP, clone.
3. **dbt docs + lineage graph:** `dbt docs generate` then `dbt docs serve` (opens in the browser).
4. **Streamlit dashboard:** Projects → Streamlit → + Streamlit App (location `HC_MIGRATION_DB.AUDIT`,
   warehouse `MIG_WH`), paste `streamlit/migration_dashboard.py`, Run.
5. **Break something on purpose.** Edit `dbt/seeds/xwalk_gender.csv` and delete the `1,M,...` row, then re-run.
   Members with legacy code `1` are now rejected with `GENDER_XWALK_NOT_FOUND`, and the scorecard still balances.
   This makes a great interview story. Put the row back afterwards.

Take screenshots for the README (`docs/images/`).

---

## Part G — Put it on GitHub (30 min)

### G1. Create the GitHub account and the repository
1. Create a free account at https://github.com. Pick a professional username, because it appears in the
   repo link on your resume.
2. Top right **+** → **New repository**:
   - Name: `snowflake-healthcare-data-migration`. Type it exactly, with **no space or hyphen at the end**
     (a trailing `-` gives *Repository not found* on push).
   - Visibility: **Public**
   - Do **not** tick *Add a README*, *.gitignore* or *license* (the project already has them)
   - **Create repository**

### G2. Create a personal access token (GitHub no longer accepts your password in Terminal)
1. GitHub → profile picture → **Settings** → **Developer settings** (bottom left) →
   **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**.
2. Note: `laptop push`, Expiration: 90 days.
3. Tick both scopes: **`repo`** and **`workflow`**. `workflow` is needed because the project contains
   `.github/workflows/` files; without it the push fails with *403* / *refusing to allow ... workflow*.
4. **Generate token** and copy it right away (it is shown only once). Keep it private: never paste it
   into a file in the project, a chat or a screenshot.

### G3. Tell Git who you are (once per laptop)
```bash
git config --global user.name  "Your Full Name"
git config --global user.email "you@example.com"     # the email of your GitHub account
```
This name is what shows as the author of every commit on GitHub.

### G4. First push
In Terminal, from the project folder:
```bash
cd /path/to/snowflake-healthcare-data-migration
git init
git add .
git status            # check: NO rsa_key.p8, NO profiles.yml, NO .venv in the list
git commit -m "Healthcare payer data migration on Snowflake + dbt"
git branch -M main
git remote add origin https://github.com/<your-username>/snowflake-healthcare-data-migration.git
git push -u origin main
```
When Git asks:
- **Username:** your GitHub username
- **Password:** paste the **token** from G2 (nothing appears while you paste; that is normal) → Enter

The Mac keychain remembers the token, so later pushes don't ask again.

If you see `error: remote origin already exists`, fix the URL instead of adding it:
```bash
git remote set-url origin https://github.com/<your-username>/snowflake-healthcare-data-migration.git
git remote -v         # check the URL is correct
```

If the push keeps failing with *403* because an old or wrong token is saved, remove it from the
keychain and push again (Git will ask for the token):
```bash
printf "protocol=https\nhost=github.com\n" | git credential-osxkeychain erase
git push -u origin main
```

### G5. Check the repository
1. Refresh the repo page: all folders and the README should be there.
2. **Actions** tab: the *dbt CI* workflow runs on every push and should show a green tick.
3. On the repo home page, click the gear next to **About** and fill in:
   - Description: `Healthcare payer data migration on Snowflake + dbt: profiling, validation, keyword
     load files and reconciliation scorecard (synthetic data)`
   - Topics: `snowflake`, `dbt`, `sql`, `data-migration`, `healthcare`, `data-engineering`,
     `stored-procedures`, `data-quality`
4. Your profile page → **Customize your pins** → pin this repo.

### G6. Add screenshots to the README
1. Take each screenshot straight to a file with **Cmd + Shift + 4** (drag over the area). It lands on
   the Desktop as a PNG.
2. Copy them into `docs/images/` with these names (the README already points to them):

   | File | What to capture |
   |---|---|
   | `scorecard.png` | Part F scorecard query result |
   | `rejects.png` | reject report query result |
   | `keyword_file.png` | the keyword file HDR / DTL records |
   | `dbt_lineage.png` | dbt lineage graph (see step 3) |

3. Lineage graph: in the `dbt` folder with the venv active run
   ```bash
   dbt docs generate
   dbt docs serve        # opens the docs in your browser; Ctrl + C in Terminal to stop
   ```
   Click the blue round icon at the bottom right of the page, then take the screenshot.
4. Make sure every file is a **real PNG**. A file saved from Preview can be a TIFF with a `.png` name,
   and GitHub shows it as a broken image:
   ```bash
   file docs/images/*.png       # every line must say "PNG image data"
   ```
   If one says TIFF: open it in Preview → **File → Export** → Format **PNG** → save over it.
5. Push:
   ```bash
   git add docs/images README.md
   git status                   # images should be listed
   git commit -m "Add screenshots"
   git push
   ```
   GitHub caches images for a few minutes, so if an image still looks broken right after the push,
   reload the page after about 5 minutes.

### G7. Every later change
```bash
git status
git add <changed files>        # or: git add .
git commit -m "Short description of the change"
git push
```

### G8. Optional: run the pipeline from GitHub
Add repository secrets `SNOWFLAKE_ACCOUNT` and `SNOWFLAKE_PRIVATE_KEY` (the full text of `rsa_key.p8`)
under *Settings → Secrets and variables → Actions*, then run **Run migration pipeline** from the
Actions tab. The key is stored encrypted by GitHub; it must never be committed as a file.

Then put the repo link on your resume and LinkedIn.

---

## Part H — Troubleshooting

| Problem | Fix |
|---|---|
| `dbt debug` → *JWT token is invalid* | Public key not set on `MIG_DBT_SVC`, or `SNOWFLAKE_PRIVATE_KEY_PATH` points to the wrong file. Re-run D3. |
| `dbt debug` → *account ... not found* | Account identifier format: use `ORGNAME-ACCOUNTNAME` (with a dash). |
| `Object does not exist or not authorized` | You're on the wrong role. Run `USE ROLE MIG_DEVELOPER;` in Snowsight; dbt uses it automatically. |
| `SP_LOAD_RAW` → *No rows loaded* | Files are not in `@RAW.SRC_STAGE/BATCH_001/`. Check with `LIST`. |
| `dbt deps` fails behind an office proxy | Try at home or ask IT; `dbt deps` downloads from hub.getdbt.com. |
| Keyword load → *Remote file was not found* | `dbt build` failed a test for that entity, so no file was created. Read the dbt output, fix, re-run. |
| `Set-ExecutionPolicy` error running the `.ps1` | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
| Masking demo shows clear data for MIG_ANALYST | Make sure you switched the **primary** role (`USE ROLE MIG_ANALYST;`). |
| `git push` → *Password authentication is not supported* | Use a personal access token as the password (G2). |
| `git push` → *Repository not found* | The repo name on GitHub and in `git remote -v` differ (check for a trailing `-` or a typo). Fix with `git remote set-url` (G4). |
| `git push` → *403* or *refusing to allow ... workflow* | Token is missing the `workflow` scope, or an old token is saved. Create a new classic token with `repo` + `workflow` and erase the keychain entry (G4). |
| `git remote add` → *remote origin already exists* | `git remote set-url origin <url>` (G4). |
| Image shows as broken on GitHub | Not pushed (`git status`), wrong name/case, or a TIFF saved as `.png` (G6 step 4). |
| `pip install` → *CERTIFICATE_VERIFY_FAILED* | Run *Install Certificates.command* from the Python 3.12 folder in Applications, then recreate the venv (D2). |

---

## Part I — Cost and cleanup

- The warehouse suspends itself after 60 seconds idle; the resource monitor stops it at 10 credits/month.
- Check usage: **Admin → Cost Management**.
- When you're completely done:
```sql
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS HC_MIGRATION_DB;
DROP WAREHOUSE IF EXISTS MIG_WH;
```
  (Your GitHub repo keeps all the code, so you can rebuild in 20 minutes any time.)
