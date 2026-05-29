# astrum-sync-action

GitHub composite action that syncs an `astrum.yml` manifest, along with the
secrets and variables it declares, to Astrum.

Authenticates via GitHub OIDC — no AWS keys required.

## Usage

```yaml
# .github/workflows/build.yml
name: build and deploy

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      env:
        type: choice
        options: [staging, prod]
        default: prod

permissions:
  contents: read
  id-token: write
  packages: write

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.env || 'prod' }}
    steps:
      - uses: actions/checkout@v4

      # ... your docker build + push steps ...

      - uses: ai-hero/astrum-sync-action@v1
        with:
          env: ${{ inputs.env || 'prod' }}
        env:
          ASTRUM_GH_VARS: ${{ toJson(vars) }}
          ASTRUM_GH_SECRETS: ${{ toJson(secrets) }}

      # ... your deploy dispatch step ...
```

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `env` | yes | — | Target environment slug. Must match a key under `environments:` in `astrum.yml`. |
| `manifest-path` | no | `astrum.yml` | Path to the manifest, relative to repo root. |
| `role-arn` | no | platform default | IAM role to assume via OIDC. |
| `aws-region` | no | `us-east-1` | AWS region. |
| `bucket` | no | platform default | Target S3 bucket. |

## Required env vars

The calling workflow must pass GitHub's `vars` and `secrets` contexts to
the action so it can resolve names declared in the manifest:

```yaml
env:
  ASTRUM_GH_VARS: ${{ toJson(vars) }}
  ASTRUM_GH_SECRETS: ${{ toJson(secrets) }}
```

Without these, names declared in the manifest resolve to empty strings.

## Schema

The `astrum.yml` contract is defined in `schemas/astrum.schema.json`.

For IDE autocomplete, add this header to your manifest:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/ai-hero/astrum-sync-action/main/schemas/astrum.schema.json
```

A minimal starter is in `examples/basic_astrum.yml`. `schemas/example.astrum.yml` is the exhaustive reference that exercises every field.

## License

MIT — see `LICENSE`.
