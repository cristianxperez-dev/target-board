# Deploying the Deadline Board to Railway

No terminal, no installing anything. Everything is done in a web browser.
About 15 minutes.

---

## What you are uploading

Put **all of these** in your GitHub repository, keeping the folder structure exactly as shown:

```
deadline-board/
│
├── public/                          ← the only folder visitors can reach
│   └── index.html                   ← the application
│
├── Dockerfile                       ← tells Railway how to run it
├── Caddyfile                        ← the web server's settings
├── docker-entrypoint.sh             ← start-up script
├── railway.json                     ← Railway settings (health check, builder)
├── .dockerignore                    ← keeps private files out of the server
├── .gitignore
├── README.md
│
├── supabase/
│   └── migrations/
│       └── 0001_init.sql            ← the database (you run this in Supabase)
│
├── test/                            ← test suites, for reference
│   ├── 00_supabase_shim.sql
│   ├── 01_rls_tests.sql
│   └── 02_server_tests.sh
│
├── AUDIT.md                         ← what relied on browser storage
├── SETUP.md                         ← the Supabase setup guide
├── PLAN.md                          ← the staged migration plan
└── RAILWAY_SETUP.md                 ← this file
```

Only the `public/` folder is served to the web. The SQL, the Dockerfile and the
documentation are in the repository for your reference but are deliberately
**not** reachable over the internet — this is tested, and verified below.

> **There is no `config.js` to upload.** Under GitHub Pages your Supabase
> settings had to be committed into the code. On Railway they come from
> environment variables instead, and `config.js` is created automatically inside
> the server each time it starts. That is why nothing sensitive goes into GitHub.

---

## Step 1 — Create the GitHub repository

1. Go to <https://github.com/new>
2. **Repository name:** `deadline-board`
3. **Visibility:** Private is fine now. (Railway can deploy from a private repo;
   GitHub Pages could not, which is one more reason this is better.)
4. Click **Create repository**

## Step 2 — Upload the files

1. On the new repository page, click **uploading an existing file**
   (or **Add file → Upload files**).
2. Drag in everything from the list above. **Drag the folders too** —
   GitHub keeps the structure.
3. Scroll down, click **Commit changes**.

Check it looks right: you should see `public`, `supabase` and `test` as folders,
and `Dockerfile`, `Caddyfile`, `railway.json` as files at the top level.

> If `Dockerfile` is missing, Railway will not know how to build. It must be at
> the top level, spelled exactly `Dockerfile` with a capital D and no extension.

## Step 3 — Create the Railway project

1. Go to <https://railway.com> and sign in with GitHub.
2. Click **New Project** → **Deploy from GitHub repo**.
3. If asked, click **Configure GitHub App** and give Railway access to your
   `deadline-board` repository, then come back.
4. Pick `deadline-board`.

Railway finds the `Dockerfile` and starts building straight away. The first
build takes 1–2 minutes. You will see the log scroll past; it finishes with
something like `serving /srv/public on port 8080`.

## Step 4 — Add your Supabase settings

In your Railway project, click the service, then the **Variables** tab.
Click **New Variable** and add these two:

| Variable name | Value |
|---|---|
| `SUPABASE_URL` | `https://xxxxxxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | the long key starting `eyJ...` |

Both come from Supabase → **Project Settings** → **API**.

Copy the key labelled **`anon` `public`** (newer projects call it
**publishable**).

> **Do not use the `service_role` / `secret` key.** It bypasses every database
> permission rule. If you paste it here by mistake the deploy will **stop with a
> clear error** rather than publishing it — that safeguard is built in and
> tested. But rotate the key in Supabase if that happens.

Railway redeploys automatically when you save. You do not need to set `PORT` —
Railway provides it and the server reads it.

## Step 5 — Turn on the public address

1. Still in the service, go to **Settings** → **Networking**.
2. Under **Public Networking**, click **Generate Domain**.
3. Railway gives you an address like
   `deadline-board-production-a1b2.up.railway.app`.

Open it. **You should see your Deadline Board, working exactly as it does
today.** HTTPS is automatic.

## Step 6 — Point Supabase at the new address

So that sign-in links go to the right place later:

1. Supabase → **Authentication** → **URL Configuration**
2. **Site URL:** your Railway address (with `https://`)
3. **Redirect URLs:** add the same address
4. Save

---

## Done

From now on, editing a file in GitHub redeploys the site automatically — usually
within a minute. There is nothing to upload by hand again.

---

## Checking it worked

Visit these on your Railway address:

| Address | What you should see |
|---|---|
| `/` | The Deadline Board |
| `/healthz` | the word `ok` |
| `/config.js` | your project URL and `configured: true` |
| `/supabase/migrations/0001_init.sql` | **404 Not Found** — correct, it is private |
| `/Dockerfile` | **404 Not Found** — correct |

If `/config.js` shows `configured: false`, the variables in Step 4 are missing
or misspelled. The Railway deploy log tells you exactly which one.

---

## Cost

Railway's free trial includes a one-off $5 of credit; after that the Hobby plan
is **$5/month and includes $5 of usage**, so a small static site like this
effectively runs inside the included allowance.

A static site uses very little: roughly 0.1 vCPU idle and about 64 MB of memory.
Expect to stay well inside the included usage.

Supabase stays on its own free tier (see `SETUP.md`). Total expected cost:
**$5/month**, versus $0 on GitHub Pages — you are paying for a real server,
private repositories, and secrets kept out of your code.

> **Worth knowing:** Railway does not sleep your service, so the Supabase
> free-tier project pausing after 7 days of inactivity is no longer masked by
> the host sleeping too. If the board sits unused for a week, open it once to
> wake Supabase.

---

## If something goes wrong

| What you see | Why | Fix |
|---|---|---|
| Build fails, `Dockerfile not found` | Files uploaded into a subfolder | Move `Dockerfile` to the top level of the repo |
| Deploy stops: "a SERVICE-ROLE key was supplied" | Wrong Supabase key | Use the `anon` / publishable key; rotate the other one |
| Site loads, `/config.js` says `configured: false` | Variables missing | Step 4; check spelling exactly |
| "Application failed to respond" | Server not on Railway's port | Do not set `PORT` yourself; let Railway set it |
| Health check failing | Build succeeded but server did not start | Open the deploy log; the last line names the problem |
| Changes not appearing | Browser cache | Hard-refresh (Ctrl/Cmd + Shift + R) |

---

## What was tested before this was handed to you

The server configuration was run for real — the actual Caddy 2.8.4 binary
against the actual `Caddyfile` and `docker-entrypoint.sh` — with **57 checks
passing**, including:

- the server honours Railway's `PORT`, and `/healthz` answers for health checks
- automatic HTTPS is off, as Railway requires (otherwise the deploy hangs)
- a `service_role` key is **refused** and never written to `config.js`
- a key containing quotes cannot inject code into `config.js`
- a missing configuration still serves the site, with a clear deploy-log message
- `config.js` is sent `no-store`, so a browser can never reuse an old key
- gzip reduces the page from 498 KB to 149 KB (71% smaller)
- the SQL migrations, `Dockerfile`, `Caddyfile` and docs all return **404**,
  including via `../` path-traversal attempts

The database suite (52 security checks) was re-run against real PostgreSQL 16
afterwards and still passes.

The one thing **not** tested end-to-end is the Docker image build itself, because
Docker Hub is not reachable from my sandbox. The `Dockerfile` is deliberately
simple — copy two files, create a user, run Caddy — and the `Caddyfile` it
depends on is fully tested. If the first Railway build fails, send me the log and
it will be a quick fix.
