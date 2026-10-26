# VPS deployment (fork only)

Runs this fork on a VPS over streamable HTTP and redeploys it on every push to the `deploy` branch.
`main` is where work is integrated; `deploy` is what runs. Pushing or syncing `main` (including
GitHub's *Sync fork*) deploys nothing. This folder exists only in the `yokuha` fork; keep it out of
upstream PR branches (cut those from `upstream/main`).

```
git push origin main:deploy ──▶ github.com ──webhook (HMAC)──▶ VPS: webhook :9000 ──▶ deploy.sh
                                                                 git pull --ff-only, uv sync, restart
```

Release = fast-forward `deploy` to a tested `main`:

```sh
git push origin main:deploy
```

| File                                | Goes to                                                                               |
|-------------------------------------|---------------------------------------------------------------------------------------|
| `deploy.sh`                         | runs from the clone, called by the webhook receiver                                   |
| `hooks.yaml`                        | read in place by the receiver; holds no secret (reads `IICU_WEBHOOK_SECRET` from env) |
| `intervals-icu-mcp.service`         | `/etc/systemd/system/`                                                                |
| `intervals-icu-mcp-webhook.service` | `/etc/systemd/system/`                                                                |

Layout: user `iicu-mcp` with home `/opt/intervals-icu-mcp` (holds `uv` in `~/.local/bin` and
caches), the clone in `/opt/intervals-icu-mcp/app`, service `intervals-icu-mcp` on `127.0.0.1:8000`,
webhook receiver on `127.0.0.1:9000`. Change them in one go if yours differ. No real hostnames, IPs
or secrets belong in this repo.


## 1. User, clone, dependencies

Create the `deploy` branch on GitHub once, from your machine: `git push origin main:deploy`.

```sh
sudo apt install webhook git
# skip if the user already exists
sudo useradd --system --home /opt/intervals-icu-mcp --create-home --shell /usr/sbin/nologin iicu-mcp
# uv for the service user, if not there yet
sudo -u iicu-mcp -H sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
sudo -u iicu-mcp -H git clone -b deploy https://github.com/yokuha/intervals-icu-mcp.git /opt/intervals-icu-mcp/app
sudo -u iicu-mcp -H sh -c 'cd /opt/intervals-icu-mcp/app && ~/.local/bin/uv sync --frozen --no-dev'
```

**Migrating an existing install** whose `app/` is not a git clone: stop the service, move it aside
(`sudo mv /opt/intervals-icu-mcp/app /opt/intervals-icu-mcp/app.old`), run the clone and `uv sync`
above, finish steps 2–4, and delete `app.old` once `/health` answers.


## 2. Credentials (on the VPS only)

```sh
sudo install -m 600 -o root -g root /dev/null /etc/intervals-icu-mcp.env
sudoedit /etc/intervals-icu-mcp.env
```

```
INTERVALS_ICU_API_KEY=...
INTERVALS_ICU_ATHLETE_ID=i123456
# secret URL path; generate the random part with: openssl rand -hex 24
MCP_PATH=/<random>/mcp
```

The MCP is then reachable only at `https://<your-host>${MCP_PATH}` — treat that URL like a
password. An existing env file keeps working as long as it has these three keys.

```sh
sudo install -m 600 -o root -g root /dev/null /etc/intervals-icu-mcp-webhook.env
echo "IICU_WEBHOOK_SECRET=$(openssl rand -hex 32)" | sudo tee /etc/intervals-icu-mcp-webhook.env
```

Keep that secret for step 6.


## 3. Allow exactly one restart without a password

`sudo visudo -f /etc/sudoers.d/iicu-mcp-deploy`:

```
iicu-mcp ALL=(root) NOPASSWD: /usr/bin/systemctl restart intervals-icu-mcp
```


## 4. Services

```sh
# sh -c: /opt/intervals-icu-mcp is 0750, so your own shell can't expand the glob
sudo sh -c 'cp /opt/intervals-icu-mcp/app/deploy/*.service /etc/systemd/system/'
sudo systemctl daemon-reload
sudo systemctl enable --now intervals-icu-mcp intervals-icu-mcp-webhook
curl -s http://127.0.0.1:8000/health    # {"status":"ok"}
```


## 5. Reverse proxy

Add the webhook path to the host that already serves the MCP. **The MCP itself has no
authentication** — the secret `MCP_PATH` plus whatever gate you have in front of it are the
protection (see [`docs/remote-deployment.md`](../docs/remote-deployment.md)); the `/hooks/`
location is protected by the HMAC check instead and must bypass any such gate.

nginx:

```
location /hooks/ {
    proxy_pass http://127.0.0.1:9000;
}
```

Caddy — wrap both routes in `handle` blocks so `/hooks/` can't fall through to the MCP
(which answers 404 for anything outside `MCP_PATH`):

```
<your-host> {
    handle /hooks/* {
        reverse_proxy 127.0.0.1:9000
    }
    handle {
        reverse_proxy 127.0.0.1:8000
    }
}
```

```sh
sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy
curl -si -X POST https://<your-host>/hooks/intervals-icu-mcp | head -1   # 403 = reachable
```


## 6. GitHub webhook

Repo → Settings → Webhooks → Add webhook:

- Payload URL: `https://<your-host>/hooks/intervals-icu-mcp`
- Content type: `application/json`
- Secret: the value of `IICU_WEBHOOK_SECRET`
- Events: *Just the push event*, SSL verification on

GitHub's initial ping gets a 403 (no `ref`, so the branch filter doesn't match) — expected,
and so do pushes to any branch other than `deploy`.


## 7. Check that a deploy arrived and ran

Run `git push origin main:deploy`, then check three places.

**GitHub — did it arrive?** Repo → Settings → Webhooks → the hook → *Recent Deliveries*.
*Redeliver* resends a delivery without a new push.

| Response | Meaning |
|---|---|
| 200 "deploy started" | signature and branch matched, `deploy.sh` started |
| 403 | no match: expected for other branches; on a `deploy` push the secret is wrong |
| 502 / timeout | Caddy doesn't forward `/hooks/`, or the receiver isn't running |

**VPS — did it run?** The receiver runs with `-verbose`, so deliveries and `deploy.sh`'s
output land in the journal. Watch live while pushing:

```sh
sudo journalctl -u intervals-icu-mcp-webhook -f
```

A deploy shows the incoming request, the matched hook, and ends with
`deploy: now at <sha>, healthy` — or the error that stopped it.

**VPS — is the new version live?**

```sh
sudo -u iicu-mcp -H git -C /opt/intervals-icu-mcp/app log --oneline -1
systemctl show intervals-icu-mcp -p ActiveEnterTimestamp
```

The commit must match `git log --oneline -1 origin/deploy` on your machine, and the start
time should be just after the push.


## Operating

* Manual deploy: `sudo -u iicu-mcp -H /opt/intervals-icu-mcp/app/deploy/deploy.sh`
* Roll back: `git revert` on `main`, then `git push origin main:deploy`. Emergency only: `git push
  --force origin <good-sha>:deploy` as repo admin (bypasses the ruleset); then run `git reset --hard
  origin/deploy` in the VPS clone, since `deploy.sh` refuses non-fast-forwards.
* `deploy.sh` only fast-forwards. Local edits on the VPS make it fail loudly instead of being
  overwritten; fix with `git status` in the clone.
* Changes to `hooks.yaml` apply on the next pull (`-hotreload`). Changes to the `.service` files
  don't — copy them again and `daemon-reload`.
* Whoever can push to `deploy` can run code on the VPS: 2FA on the GitHub account, and the ruleset
  on `deploy` (only the repo admin may push, no force pushes) stay on. `main` needs none: it
  deploys nothing.
* Claude Code sessions on the dev machine are blocked from pushing `deploy` by a local pre-push hook
  plus deny rules; releasing is always a human `git push origin main:deploy`.
