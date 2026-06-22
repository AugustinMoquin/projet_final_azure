# Projet Azure — Cloud Asynchronous Pipeline (AI, Notifications, DLQ)

Event-driven document pipeline on Azure: a file lands in Blob Storage, a Function
publishes it to Service Bus, a processor Function tags it with AI and writes
metadata to Cosmos DB, real-time status is pushed to a React app via SignalR, and
failures are routed to a Dead Letter Queue handled by a dedicated Function.

Infrastructure is **Terraform**; deployment is a **GitHub Actions** pipeline.

## Architecture

```
        upload                publish               process + AI tag
  ┌──────────────┐  blob   ┌──────────────┐  msg  ┌──────────────────┐
  │ Blob Storage │────────▶│ Blob-trigger │──────▶│   Service Bus    │
  │ (documents)  │         │   Function   │       │  documents-queue │
  └──────────────┘         └──────┬───────┘       └────────┬─────────┘
                                  │ UPLOADED               │
                                  ▼ (SignalR)              ▼
                           ┌─────────────┐        ┌──────────────────┐
                           │  React app  │◀───────│  Processor Func  │
                           │  (SignalR)  │ status │ AI tags + Cosmos │
                           └─────────────┘        └────────┬─────────┘
                                  ▲                         │ on 5 failures
                                  │ ERROR                   ▼
                           ┌──────┴───────┐        ┌──────────────────┐
                           │  DLQ Func    │◀───────│ $DeadLetterQueue │
                           └──────────────┘        └──────────────────┘

  Observability: Application Insights (correlationId, documentId)
```

## Repository layout

```
terraform/           All Azure infrastructure as code
.github/workflows/   GitHub Actions CI/CD pipeline (deploy.yml)
WALKTHROUGH.md       Step-by-step for the manual parts — START HERE
backend/             Azure Functions (Python) — your app code
frontend/            React app — your app code
```

## Quick start

Follow [WALKTHROUGH.md](WALKTHROUGH.md). In short:

1. Install Terraform + Azure CLI, `az login`.
2. (Optional) request Azure OpenAI access — or set `enable_openai = false`.
3. `cd terraform && terraform init && terraform apply`.
4. Enable the static-website toggle, set GitHub secrets.
5. Push to `main` → pipeline deploys Functions + React.

## What's infra vs. app code

This repo ships the **infrastructure + pipeline + manual runbook** complete. The
`backend/` (Functions) and `frontend/` (React) directories hold your application
code; the pipeline expects:

- `backend/requirements.txt` and the Functions (Python v2 programming model).
- `frontend/package.json` with a `build` script producing `frontend/dist`.

The Terraform-provisioned app settings the Functions read are documented in
[terraform/functions.tf](terraform/functions.tf):
`DOCS_STORAGE_CONNECTION`, `SERVICEBUS_CONNECTION`, `COSMOS_*`,
`AzureSignalRConnectionString`, `OPENAI_*`.

## A note on the brief

The brief says "GitLab CI/CD" — that is a typo; this project uses **GitHub
Actions**. It also lists `AZURE_CLIENT_SECRET` as a required variable; we use
**OIDC federated credentials** instead (no stored secret), which is the more
secure modern approach. Service-specific credentials (Cosmos, Service Bus,
SignalR, OpenAI) are injected as Function App settings by Terraform rather than
stored in the CI system.
