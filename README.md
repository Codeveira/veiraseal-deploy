# Veira Seal — deploy

Everything needed to run your own Veira Seal instance: a Docker Compose
stack, a reverse-proxy example, and backup/upgrade scripts. This is a
generic secrets-vault deployment — it stores secrets for whatever projects
you point it at, not just Codeveira (a paid Codeveira licence happens to
unlock the paid Veira Seal tiers at no extra cost; see the main
[`../veiraseal`](../veiraseal) README's Licensing section).

## Requirements

- Docker Engine 24+ and the `docker compose` plugin (v2).
- A place to write two files outside of git: the master key file and the
  one-time recovery key. Losing both means the vault's data cannot be
  recovered — there is no backdoor, by design.

Before changing anything here, `make check` (or `./check.sh`) validates
`backup.sh`/`upgrade.sh` syntax and `docker-compose.yml` — no Docker
daemon required, just the CLI.

## Quick start

```sh
cp .env.example .env
$EDITOR .env   # set VEIRA_ADMIN_PASSWORD

make init      # creates the vault, prints the recovery key ONCE — save it offline
make up        # starts the server on 127.0.0.1:8200
make ps        # check it's healthy
```

Without `make`, the same three steps are:

```sh
mkdir -p data backup
chmod 777 data   # image runs as a fixed distroless nonroot UID (65532)
docker compose run --rm veira-init
docker compose up -d veira
docker compose ps
```

By default the port is bound to `127.0.0.1` only. Put a reverse proxy in
front for real TLS and a public hostname — see
[`nginx.conf.example`](nginx.conf.example) — or change the `ports:` line in
`docker-compose.yml` if you're terminating TLS elsewhere (a load balancer,
Cloudflare, etc).

## Where things live

```
./data/veira.db     the encrypted database (bind-mounted into the container)
./data/veira.key     the master key file — back this up separately from ./data
./backup/            timestamped snapshots from backup.sh / make backup
```

`veira.key` and the recovery key printed by `make init` are the only two
things that can unseal the vault. Keep at least one of them somewhere that
isn't this server (a password manager, an offline drive) — a disk failure
that takes `./data` with it also takes the key file.

## Updating

```sh
make upgrade   # backs up, then pulls IMAGE_TAG from .env and recreates the container
```

Or pin a specific version:

```sh
./upgrade.sh 0.2.0
```

`upgrade.sh` refuses to pull/recreate if the backup step fails, so a bad
upgrade never costs you your last good snapshot.

To roll back, set `IMAGE_TAG` in `.env` back to the previous tag and
`make up` — the on-disk format is stable across patch/minor versions
within a major version (see `../veiraseal/DECISIONS.md` upstream, if you
have access to it, or the release notes for the tag you're rolling back to).

See [`CHANGELOG.md`](CHANGELOG.md) for what changed in this deployment
stack itself (Compose file, scripts, Makefile) across versions.

## Backup & restore

```sh
make backup                 # snapshot -> ./backup/veira-<timestamp>.db
```

To restore: stop the stack, replace `./data/veira.db` with a snapshot from
`./backup/`, then `make up` with the original `./data/veira.key` (or the
recovery key, via `veira server backup`'s companion `UnsealWithRecovery`
path documented in the main README) still in place. Backups are encrypted
ciphertext-only — a stolen backup file is useless without the key.

## Security notes

- Never put `VEIRA_ADMIN_PASSWORD`, the master key, or the recovery key
  into `.env` beyond the one-time init step above — `.env` is read by
  `docker compose` on every command and is easy to accidentally commit or
  log. The admin password in `.env` is only read once, by `veira-init`.
- Set `VEIRA_TRUST_PROXY=1` in `.env` **only** if the nginx (or equivalent)
  in front of this container is the sole path to it — otherwise a client
  can spoof its own IP in the audit log and dodge the rate limiter via
  `X-Forwarded-For`.
- The container ships as a distroless, non-root, shell-less image on
  purpose; everything above works through Compose/env vars, never through
  `docker exec sh` into the container.
