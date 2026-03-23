# Bootstrap

End-to-end setup scripts that create a GitHub repo, configure a Google Cloud project, and wire up a CI/CD pipeline using GitHub Actions and Cloud Run.

## What it does

Running `main.sh` walks you through:

1. **Preflight checks** - verifies you're in a git repo, the required workflow file exists, and the CLI tools you need are installed and authenticated.
2. **GitHub repo setup** - creates the remote repo and configures the origin remote.
3. **Google Cloud project setup** - creates or selects a GCP project, enables required APIs, and sets up Artifact Registry.
4. **IAM & Workload Identity Federation** - creates service accounts, assigns roles, and configures keyless auth between GitHub Actions and GCP.
5. **Deployment** - writes repo configuration, dispatches the deploy workflow, and sets up Cloud Run services for service and/or client targets.

## Prerequisites

- `git`, `gh` (GitHub CLI), and `gcloud` (Google Cloud CLI) installed and authenticated
- A `.github/workflows/client-deploy.yml` workflow file in your project
- Run from inside a git repository

## Usage

### Interactive mode

```bash
./bootstrap/main.sh
```

You'll be prompted for your repo name, GCP project, deployment targets, and service configuration.

### Non-interactive (E2E) mode

```bash
GITHUB_REPO_FULL=org/repo-name \
PROJECT_ID=my-gcp-project \
VITE_API_BASE_URL=https://api.example.com \
./bootstrap/run-e2e.sh
```

Optional environment variables for `run-e2e.sh`:

| Variable | Default |
|---|---|
| `REGION` | `us-central1` |
| `GAR_REPOSITORY` | `app-images` |
| `DEPLOYER_SA_ID` | `github-deployer` |
| `RUNTIME_SA_ID` | `cloudrun-runtime` |
| `WIF_POOL_ID` | `github` |
| `WIF_PROVIDER_ID` | repo name |

### Running tests

```bash
./bootstrap/run-tests.sh
```

Runs all test files under `bootstrap/tests/` and prints a pass/fail summary.