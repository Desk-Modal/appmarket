---
description: "Build to dist/ and launch DeskModal. CI must pass first. dist/ IS the runtime — no copying needed."
user-invocable: true
---

# /deploy [target]

Build artifacts into `dist/` under the repo root. DeskModal runs directly from `dist/`.

## Targets

| Target | Action |
|--------|--------|
| `/deploy` | Build everything into dist/ (same as `/build bundle`) |
| `/deploy plugin` | Build + sign TradeSurface plugin into dist/plugins/ |
| `/deploy service <name>` | Build + sign single service into dist/plugins/deskmodal/services/ |

## RULE: CI must pass before any deploy or launch

**NEVER** deploy or launch without a passing local CI gate:
- At minimum: `./scripts/local-ci.sh --fast` (fmt + clippy + typecheck)
- For production: `./scripts/local-ci.sh --full --sign` (full gates + dist build + signing)
- Use `./scripts/launch.sh --build` to run CI + build + launch as one pipeline.

## Execution Steps

1. **Run local CI** — `./scripts/local-ci.sh --fast` (or `--full`). **BLOCKING.**
2. **Graph scope** — `detect_changes(project=<platform-project>  # resolve via list_projects())` to rebuild only changed components.
3. **Build dist** — `./scripts/build-dist.sh --sign`. All output goes to `dist/`.
4. **Verify** — check dist/ has the binary, signed services, and apps.
5. **Launch** — `./scripts/launch.sh`. Runs directly from dist/.

## Directory Model

```
dist/                                    # CI output — DeskModal runs from here
├── platform/{os}-{arch}/DeskModal{.exe} # Agent binary
├── plugins/deskmodal/                   # Plugin bundle
│   ├── plugin.toml + publisher.pub
│   ├── apps/{name}/index.html           # Web apps
│   └── services/{os}-{arch}/*.dll + .sig # Signed services
└── config/desk.toml + manifests/

~/.deskmodal/                            # User data ONLY (not app/plugin binaries)
├── logs/                                # Structured logs
├── data/                                # SQLite, storage
└── keys/                                # Crypto keys
```

**No copying from dist/ to ~/.deskmodal/.** The binary and plugins stay in dist/.

## Signing

Service binaries are signed during build:
```bash
./scripts/sign-service.sh price-feed    # Signs into dist/plugins/deskmodal/services/{os}-{arch}/
```

Dev keypair auto-generated on first sign. CI uses production keys.
