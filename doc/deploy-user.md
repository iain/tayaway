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
```

Verify you can log in, and that SSH agent forwarding still reaches GitHub
(Capistrano needs this for `git fetch` during the deploy):

```sh
ssh -p 50022 tayaway@tayaway.nl
ssh -p 50022 -A tayaway@tayaway.nl 'ssh -T git@github.com'
# expected: Hi iain! You've successfully authenticated, but GitHub does not provide shell access.
```

## 2. Sudoers

Capistrano's Falcon tasks need a narrow set of root commands. Drop a
fragment in `/etc/sudoers.d/tayaway` (`sudo visudo -f /etc/sudoers.d/tayaway`):

```
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
```

Then `sudo chmod 0440 /etc/sudoers.d/tayaway` and confirm with
`sudo visudo -c`. Nothing else — no general sudo, no shell escapes.

## 3. mise toolchain for tayaway

Install mise itself, then provision the Ruby/Node/pnpm versions from the
repo's `.mise.toml`. This step compiles Ruby from source (5–10 minutes) —
do it now, outside the cutover window, so any compile failure surfaces
here instead of mid-deploy:

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

## 4. Postgres role

The intent: `tayaway` keeps full read/write/DDL access on the contents of
`tayaway_production` (so migrations work) but loses any privilege that
would let it drop the database itself.

Connect as the postgres superuser: `sudo -u postgres psql`.

```sql
-- Inspect current state — keep this output, it's your rollback reference.
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication
FROM pg_roles WHERE rolname = 'tayaway';
SELECT datname, pg_get_userbyid(datdba) AS owner
FROM pg_database WHERE datname = 'tayaway_production';
```

If the role doesn't exist yet, create it (use the password already in
`/var/www/tayaway/shared/backend/.env.production`):

```sql
CREATE ROLE tayaway WITH LOGIN PASSWORD '<password from .env.production>'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT;
```

If it exists, strip any dangerous attributes:

```sql
ALTER ROLE tayaway NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
```

Move database ownership off `tayaway` if it currently sits there. **This
is the line that takes away DROP DATABASE** — without owner status and
without superuser, `DROP DATABASE` is rejected:

```sql
ALTER DATABASE tayaway_production OWNER TO postgres;
GRANT CONNECT ON DATABASE tayaway_production TO tayaway;
```

Inside the database, make sure `tayaway` can still create and alter
objects (this is what migrations need):

```sql
\c tayaway_production
GRANT USAGE, CREATE ON SCHEMA public TO tayaway;

-- If any existing tables/sequences are owned by postgres or another role,
-- hand them to tayaway so future migrations can ALTER/DROP them.
REASSIGN OWNED BY postgres TO tayaway;
```

Verify the constraint with a read-only catalog assertion. Postgres allows
`DROP DATABASE` only for the database owner or a superuser, so confirming
that `tayaway` is neither is logically equivalent to confirming it cannot
drop the database — without ever issuing the destructive statement:

```sql
SELECT
  CASE
    WHEN (SELECT rolsuper FROM pg_roles WHERE rolname = 'tayaway')
      THEN 'FAIL: tayaway is a superuser'
    WHEN (SELECT pg_get_userbyid(datdba) FROM pg_database
          WHERE datname = 'tayaway_production') = 'tayaway'
      THEN 'FAIL: tayaway owns tayaway_production'
    ELSE 'OK: tayaway cannot drop tayaway_production'
  END AS dropdb_check;
```

`OK: tayaway cannot drop tayaway_production` is the success condition.
Anything else means stop and re-check the previous steps before continuing
to the cutover — do **not** issue a real `DROP DATABASE` to "verify" the
restriction.

For completeness, the same view as raw catalog rows (useful as a rollback
reference; superuser/createdb/createrole/replication should all be `f`,
and the database owner should not be `tayaway`):

```sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolreplication
FROM pg_roles WHERE rolname = 'tayaway';
SELECT datname, pg_get_userbyid(datdba) AS owner
FROM pg_database WHERE datname = 'tayaway_production';
```

Finally, confirm `pg_hba.conf` accepts the role over TCP — the backup
script connects via `DATABASE_URL` (TCP localhost) rather than peer auth,
so this auth path has to work end-to-end. As `tayaway`:

```sh
psql "$(grep -E '^DATABASE_URL=' /var/www/tayaway/shared/backend/.env.production \
        | cut -d= -f2- | tr -d '"'"'")" -c 'SELECT 1;'
# expected: a single-row result, no auth errors
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

Then take a fresh encrypted backup right before the cutover. The nightly
cron only runs at 03:00, so without this step the freshest dump may be up
to 24 h old — and the next 24 h is exactly when something might go wrong:

```sh
sudo -u tayaway /var/www/tayaway/current/config/deploy/backup-db.sh
ls -lh /var/www/tayaway/shared/backups/ | tail -3
```

## 6. Cutover (downtime window)

The cutover is a normal full deploy — the first one running as `tayaway`.
That exercises every Capistrano task under the new user (`mise install`,
`bundle install`, frontend build, migrations, unit render, restart) and
catches any remaining permission gap inside the deploy flow rather than
afterwards. A `falcon:install_unit`-only swap would skip Bundler bin-stub
regeneration and is only safe if §3 was completed exactly.

Dry-run first to validate paths and SSH:

```sh
bundle exec cap production deploy:check
```

Then the real cutover from your laptop:

```sh
bundle exec cap production deploy
```

Capistrano connects as `tayaway`, runs migrations against the restricted
Postgres role (which now has table-level DDL but no DROP DATABASE),
re-renders the systemd unit with `User=tayaway`, and restarts Falcon.
The downtime window is the `systemctl restart` itself — a few seconds.

Verify on the server:

```sh
sudo systemctl status tayaway-falcon       # active (running)
ps -o user= -p "$(systemctl show -p MainPID --value tayaway-falcon)"   # → tayaway
curl -sS http://127.0.0.1:9292/api/health  # → {"status":"healthy"}
sudo journalctl -u tayaway-falcon -n 100 --no-pager
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

**During `cap production deploy`, before `falcon:restart`** — the old
ubuntu-owned Falcon is still running and serving traffic. Investigate
the failed task, fix, and re-run. No traffic impact.

**`falcon:restart` ran but the new tayaway-owned Falcon won't stay up**
(see `journalctl -u tayaway-falcon`). Roll the systemd side back without
touching the Postgres role:

```sh
# On the server: hand files back to ubuntu and edit the unit in place.
sudo chown -R ubuntu:ubuntu /var/www/tayaway
sudo sed -i 's/^User=tayaway$/User=ubuntu/; s/^Group=tayaway$/Group=ubuntu/; s|/home/tayaway/|/home/ubuntu/|g' /etc/systemd/system/tayaway-falcon.service
sudo systemctl daemon-reload
sudo systemctl restart tayaway-falcon
```

Then locally `git revert <commit>` so the next deploy doesn't reapply the
change.

**The Postgres role change needs reverting** (rare — none of the changes
in §4 affect a running app's connections). `ALTER DATABASE
tayaway_production OWNER TO tayaway;` puts ownership back, and `ALTER
ROLE tayaway SUPERUSER;` (if that's what it was before) restores the
previous attributes.
