# Restricted deploy user

Production runs everything as a Linux user `tayaway` and a Postgres role of
the same name. The role can read, write, and migrate `tayaway_production`
but is **not** the database owner and **not** a Postgres superuser, so it
cannot drop the database. Capistrano deploys, the Falcon systemd unit, and
the nightly backup cron all run as this user.

The repo holds the configuration; the steps below cover the one-time
server setup and cutover from the previous `ubuntu` user.

## 1. Linux user

As the existing `ubuntu` user (or any user with sudo):

```sh
sudo useradd --create-home --shell /bin/bash tayaway
sudo -u tayaway mkdir -p /home/tayaway/.ssh
sudo -u tayaway chmod 700 /home/tayaway/.ssh

# Authorise the same SSH keys you use to deploy as ubuntu
sudo cp /home/ubuntu/.ssh/authorized_keys /home/tayaway/.ssh/authorized_keys
sudo chown tayaway:tayaway /home/tayaway/.ssh/authorized_keys
sudo chmod 600 /home/tayaway/.ssh/authorized_keys

# Inherit ubuntu's known_hosts so outbound SSH (notably git@github.com
# during deploys) doesn't trip on host-key verification. ubuntu has
# accumulated these entries over real prior deploys, so copying is at
# least as trustworthy as a fresh ssh-keyscan.
sudo cp /home/ubuntu/.ssh/known_hosts /home/tayaway/.ssh/known_hosts
sudo chown tayaway:tayaway /home/tayaway/.ssh/known_hosts
sudo chmod 600 /home/tayaway/.ssh/known_hosts
```

The Capistrano deploy reaches GitHub from the server via a deploy key in
ubuntu's `~/.ssh/`, not via agent forwarding from your laptop. tayaway
needs its own key registered as a separate deploy key on the repo — that
way revoking ubuntu's access later is a single GitHub UI click and
doesn't touch tayaway:

```sh
sudo -u tayaway ssh-keygen -t ed25519 -N '' \
  -f /home/tayaway/.ssh/id_ed25519 \
  -C 'tayaway@tayaway.nl deploy'
sudo cat /home/tayaway/.ssh/id_ed25519.pub
```

Add the printed public key to https://github.com/iain/tayaway/settings/keys
as a new deploy key. Read-only is sufficient — Capistrano only fetches.

Verify the SSH chain end-to-end:

```sh
ssh -p 50022 tayaway@tayaway.nl 'ssh -T git@github.com'
# expected: Hi iain/tayaway! You've successfully authenticated, but GitHub does not provide shell access.
```

## 2. Sudoers

Capistrano's Falcon tasks need a narrow set of root commands. Use a
validate-then-install workflow rather than `visudo -f` directly —
`visudo -f` runs a lockout heuristic that false-positives on files that
only grant rules to other users (like this one), and you'd have to
override its scary "lock me out and Save" prompt every time:

```sh
cat > /tmp/tayaway-sudoers <<'EOF'
Cmnd_Alias TAYAWAY_FALCON = \
  /usr/bin/mv /tmp/tayaway-falcon.service /etc/systemd/system/tayaway-falcon.service, \
  /usr/bin/systemctl daemon-reload, \
  /usr/bin/systemctl start tayaway-falcon, \
  /usr/bin/systemctl stop tayaway-falcon, \
  /usr/bin/systemctl restart tayaway-falcon, \
  /usr/bin/systemctl reload tayaway-falcon, \
  /usr/bin/systemctl status tayaway-falcon, \
  /usr/bin/systemctl is-active --quiet tayaway-falcon

tayaway ALL=(root) NOPASSWD: TAYAWAY_FALCON
EOF

sudo visudo -c -f /tmp/tayaway-sudoers     # syntax check in isolation
sudo install -m 0440 -o root -g root /tmp/tayaway-sudoers /etc/sudoers.d/tayaway
rm /tmp/tayaway-sudoers
sudo visudo -c                              # parses the whole chain
```

`visudo -c` at the end reports `parsed OK` if the main sudoers plus
every `/etc/sudoers.d/*` file load without error — that's the real
"you didn't break anything" confirmation. Nothing else for tayaway —
no general sudo, no shell escapes.

## 3. mise toolchain for tayaway

mise compiles Ruby from source via `ruby-build`, which needs a fairly
specific set of -dev packages. Don't assume they're present even if
ubuntu deploys today — pre-existing Ruby installs may be system-packaged
or cached. Install the canonical ruby-build dependency set first
(harmless to re-run if some are already there):

```sh
sudo apt-get install -y \
  autoconf patch build-essential rustc \
  libssl-dev libyaml-dev libreadline-dev zlib1g-dev \
  libgmp-dev libncurses-dev libffi-dev libgdbm-dev libdb-dev uuid-dev
```

Then install mise itself and provision the Ruby/Node/pnpm versions from
the repo's `.mise.toml`. The Ruby compile takes 5–10 minutes; doing it
now (outside the cutover window) means any failure surfaces here
instead of mid-deploy:

```sh
sudo -iu tayaway
curl https://mise.run | sh
echo 'eval "$(/home/tayaway/.local/bin/mise activate bash)"' >> ~/.bashrc
mise trust /var/www/tayaway      # silences the trust prompt for deploys

# Provision Ruby/Node/pnpm against the live release. The systemd unit's
# PATH points at /home/tayaway/.local/share/mise/installs/ruby/<ver>/bin
# — that directory has to exist before the cutover restart.
cd /var/www/tayaway/current && mise install --yes
mise exec -- ruby -v && mise exec -- node -v && mise exec -- pnpm -v
exit
```

If `mise install` fails partway with "Could not be configured" for
psych or fiddle, the missing package is `libyaml-dev` or `libffi-dev`
respectively — install whichever apt complained was missing, then
`rm -rf ~/.local/share/mise/installs/ruby/<version>` and retry.

## 4. Postgres role

The app authenticates to Postgres via Unix-socket peer auth — the
`DATABASE_URL` in `.env.production` looks like
`postgres://%2Fvar%2Frun%2Fpostgresql/tayaway_production`, with no user
or password component. So whichever OS user runs Falcon, that's the
Postgres role it connects as. Today that's `ubuntu`; after the cutover
it's `tayaway`. The role rename is what makes the swap atomic.

Connect as the postgres superuser: `sudo -u postgres psql`.

First, confirm the current state — what role owns the database, and
what relevant roles already exist:

```sql
SELECT 'database' AS kind, datname AS name, pg_get_userbyid(datdba) AS owner
FROM pg_database WHERE datname = 'tayaway_production'
UNION ALL
SELECT 'role', rolname, NULL FROM pg_roles
WHERE rolname IN ('ubuntu', 'tayaway', 'postgres');
```

Two cases follow from the inspection — the rest of this section
branches on which one matches.

**Case A — only `ubuntu` exists.** Cleanest path: lock in the safety
property pre-cutover, then atomically `ALTER ROLE ubuntu RENAME TO
tayaway` at §6. Every grant and ownership relation moves with the role
because Postgres tracks them by OID, not by name.

**Case B — both `ubuntu` and `tayaway` already exist.** Use
`REASSIGN OWNED BY` at §6 instead of a rename. The pre-cutover work is
the same shape but tightens both roles and ensures `tayaway` is set up
to receive ownership.

Both cases share the same pre-cutover statements; the only difference is
that Case B tightens `tayaway` too and grants it connect/schema access
in advance. None of this affects existing connections — connection-level
metadata isn't re-checked, and ownership of objects the role still
effectively controls is unchanged:

```sql
-- Strip dangerous attributes. Run the second line only in Case B.
ALTER ROLE ubuntu  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
ALTER ROLE tayaway NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;  -- Case B

-- Move database ownership off the role the app connects as. After this,
-- DROP DATABASE requires either superuser or being the database owner —
-- and we've just removed both.
ALTER DATABASE tayaway_production OWNER TO postgres;

-- Case B only: tayaway needs to be able to connect and create objects
-- before §6's REASSIGN hands it the table ownership.
GRANT CONNECT ON DATABASE tayaway_production TO tayaway;            -- Case B
\c tayaway_production
GRANT USAGE, CREATE ON SCHEMA public TO tayaway;                    -- Case B
```

Verify the constraint with a read-only catalog assertion. Postgres
allows `DROP DATABASE` only for the database owner or a superuser, so
confirming the app's role is neither is logically equivalent to
confirming it cannot drop the database — without ever issuing the
destructive statement:

```sql
SELECT
  CASE
    WHEN (SELECT rolsuper FROM pg_roles WHERE rolname = 'ubuntu')
      THEN 'FAIL: ubuntu is a superuser'
    WHEN (SELECT pg_get_userbyid(datdba) FROM pg_database
          WHERE datname = 'tayaway_production') = 'ubuntu'
      THEN 'FAIL: ubuntu owns tayaway_production'
    ELSE 'OK: ubuntu cannot drop tayaway_production'
  END AS dropdb_check;
```

`OK: ubuntu cannot drop tayaway_production` is the success condition.
Anything else means stop and re-check the previous steps before
continuing — do **not** issue a real `DROP DATABASE` to "verify" the
restriction. The same property survives the rename in §6.

Finally, sanity-check that peer auth and the socket URL work end-to-end
as the new OS user. The role doesn't exist under that name yet, so
expect a peer-auth failure here — that's the diagnostic, not a problem:

```sh
sudo -u tayaway psql "$(grep -E '^DATABASE_URL=' \
  /var/www/tayaway/shared/backend/.env.production | cut -d= -f2-)" \
  -c 'SELECT 1;' || true
# expected: FATAL: role "tayaway" does not exist
# anything else (e.g. socket missing, connection refused) means
# pg_hba.conf or the socket directory needs attention before §6.
```

## 5. File ownership

Hand the deploy tree over while the old `ubuntu`-owned Falcon is still
serving traffic. `chown -R` is safe; the files don't move.

```sh
sudo chown -R tayaway:tayaway /var/www/tayaway
sudo -u tayaway mkdir -p /var/www/tayaway/shared/log
```

Confirm `/var/www/tayaway/shared/backend/.env.production` is still
readable by `tayaway` and not world-readable:

```sh
sudo -u tayaway cat /var/www/tayaway/shared/backend/.env.production >/dev/null
ls -l /var/www/tayaway/shared/backend/.env.production
sudo chmod 600 /var/www/tayaway/shared/backend/.env.production
```

A fresh pre-cutover backup is part of §6 below — it has to wait until
after the role rename (Case A) or REASSIGN (Case B) so the same
peer-auth path the script uses at runtime is exercised end to end.

## 6. Cutover (downtime window)

The cutover has three moves that have to happen in order: stop the
ubuntu falcon, rename the Postgres role atomically, then deploy as the
new user. Renaming with falcon running would break its peer-auth
mid-flight (new connections would fail with "role 'ubuntu' does not
exist"); renaming after the deploy would mean tayaway-falcon comes up
unable to connect. So: stop, rename, deploy.

Dry-run from your laptop first to validate paths and SSH:

```sh
bundle exec cap production deploy:check
```

Then on the server, stop ubuntu's falcon and move ownership over —
which statement to run depends on which §4 case matched:

```sh
sudo systemctl stop tayaway-falcon

# Case A (rename, only ubuntu existed):
sudo -u postgres psql -c 'ALTER ROLE ubuntu RENAME TO tayaway;'

# Case B (REASSIGN, both roles existed):
sudo -u postgres psql -d tayaway_production \
  -c 'REASSIGN OWNED BY ubuntu TO tayaway;'
```

Both moves are atomic and instant — the rename takes every grant and
ownership relation with it; REASSIGN hands every ubuntu-owned table,
sequence, and function to tayaway in one statement.

Now take the pre-cutover backup. The nightly cron only runs at 03:00,
so without this step the freshest dump may be up to 24 h old — and the
next few minutes are exactly when something might go wrong. The
ownership transfer above means tayaway can now read every table, so
the same peer-auth code path cron uses works here:

```sh
sudo -u tayaway /var/www/tayaway/current/config/deploy/backup-db.sh
ls -lh /var/www/tayaway/shared/backups/ | tail -3
```

If this fails, **stop and reverse the ownership transfer** before
continuing — see the rollback section. Don't deploy without a recent
backup.

From the laptop, deploy:

```sh
bundle exec cap production deploy
```

Capistrano connects as `tayaway`, peer-authenticates to the renamed
Postgres role, runs migrations (the role still owns the tables), runs
`mise install` / `bundle install` / frontend build, re-renders the
systemd unit with `User=tayaway`, and starts Falcon. The downtime
window is from the `systemctl stop` above through the deploy's final
`falcon:restart` — a couple of minutes.

Verify on the server:

```sh
sudo systemctl status tayaway-falcon       # active (running)
ps -o user= -p "$(systemctl show -p MainPID --value tayaway-falcon)"   # → tayaway
curl -sS http://127.0.0.1:9292/api/health  # → {"status":"healthy"}
sudo journalctl -u tayaway-falcon -n 100 --no-pager
sudo -u postgres psql -c "
  SELECT
    CASE
      WHEN (SELECT rolsuper FROM pg_roles WHERE rolname = 'tayaway')
        THEN 'FAIL: tayaway is a superuser'
      WHEN (SELECT pg_get_userbyid(datdba) FROM pg_database
            WHERE datname = 'tayaway_production') = 'tayaway'
        THEN 'FAIL: tayaway owns tayaway_production'
      ELSE 'OK: tayaway cannot drop tayaway_production'
    END;"
```

If any of these don't look right, see the rollback section.

## 7. Cron

Drop the entry from ubuntu's crontab and re-create it under tayaway,
pointing the log at `shared/log/` (which tayaway can write to):

```sh
sudo crontab -u ubuntu -l | grep -v backup-db.sh | sudo crontab -u ubuntu -
sudo -iu tayaway
crontab -e
```

Add:

```
0 3 * * * /var/www/tayaway/current/config/deploy/backup-db.sh >> /var/www/tayaway/shared/log/backup.log 2>&1
```

Run it once by hand to confirm:

```sh
sudo -u tayaway /var/www/tayaway/current/config/deploy/backup-db.sh
ls -l /var/www/tayaway/shared/backups/
```

## 8. Subsequent deploys

Plain `bundle exec cap production deploy`, same as before — only the SSH
user has changed. No further special handling.

You can leave the `ubuntu` account in place; nothing references it any
more. Removing it is a separate cleanup.

## Rollback

Failure modes split by where the cutover broke:

**Before §6's `systemctl stop`** — nothing has been swung yet. The §4
changes (role attributes, database owner) don't affect the running
app's connections, so just back them out at leisure:
`ALTER DATABASE tayaway_production OWNER TO ubuntu;` and `ALTER ROLE
ubuntu SUPERUSER;` (if that's what it was — keep §4's "current state"
output as the reference).

**§6's role move succeeded but the deploy fails** — ubuntu's falcon
can't come back up cleanly until ownership is back on ubuntu. Reverse
whichever move you made and bring ubuntu's falcon back:

```sh
# If §6 was Case A (rename), reverse the rename:
sudo -u postgres psql -c 'ALTER ROLE tayaway RENAME TO ubuntu;'

# If §6 was Case B (REASSIGN), reverse the ownership transfer:
sudo -u postgres psql -d tayaway_production \
  -c 'REASSIGN OWNED BY tayaway TO ubuntu;'

sudo chown -R ubuntu:ubuntu /var/www/tayaway
sudo sed -i 's/^User=tayaway$/User=ubuntu/; s/^Group=tayaway$/Group=ubuntu/; s|/home/tayaway/|/home/ubuntu/|g' /etc/systemd/system/tayaway-falcon.service
sudo systemctl daemon-reload
sudo systemctl start tayaway-falcon
```

Then locally `git revert <commit>` so the next deploy doesn't reapply
the change.

**Tayaway falcon started but is misbehaving at runtime** — same recovery
as above (rename role back, chown back, edit unit, restart). Investigate
the misbehaviour out of band before re-attempting the cutover.
