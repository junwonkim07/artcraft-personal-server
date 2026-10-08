# Contributing

Thanks for helping make personal deployments easier to reproduce.

## Report a problem

Open an issue with your operating system and CPU architecture, Docker/Compose versions,
the upstream revision from `UPSTREAM.lock`, reproduction steps, and relevant logs.
Remove passwords, tokens, cookies, email addresses, and private server details before posting.

## Make a change

1. Fork the repository and create a branch.
2. Keep changes focused. Explain the behavior being fixed and the validation you performed.
3. Run the checks below, then open a pull request.

```bash
./scripts/secret-scan.sh
for file in scripts/*.sh docker/*.sh; do bash -n "$file"; done
shellcheck -x scripts/*.sh docker/*.sh
# After generating your local secrets:
docker compose config --quiet
```

For deployment changes, also build and start the stack, check its health, and test the
affected workflow. Do not describe a change as runtime-verified if it has only passed
static checks. Never commit `.env`, provider credentials, database dumps, or user media.

## Upstream patches

Keep patches minimal and tied to the revision in `UPSTREAM.lock`. Preserve upstream
behavior when an override is unset. Do not remove upstream community, donation, or paid
model links. Upstream-derived patches retain the upstream license; see `LICENSE-NOTICE.md`.

## Documentation

The README is the project overview and quick start. Detailed operational instructions
belong under `docs/ko/`. Include examples that work on a clean installation and distinguish
required steps from optional settings.
