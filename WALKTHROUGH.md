# Walkthrough — what you do by hand

Terraform creates all the Azure resources. But a few things **cannot** (or should
not) be done by Terraform and you must do them manually. This file is the ordered
checklist. Do the steps top to bottom.

> Note on the brief: it says "GitLab CI/CD". That's a typo — we use **GitHub
> Actions** (`.github/workflows/deploy.yml`). Everywhere the brief says "GitLab
> CI/CD variables", read "GitHub repository secrets".

---

## 0. Install the tools (one time, on your machine)

```powershell
# Run in PowerShell. winget ships with Windows 10/11.
winget install Hashicorp.Terraform
winget install Microsoft.AzureCLI
winget install Git.Git
winget install GitHub.cli        # optional, makes secret-setting easier
```

Close and reopen your terminal afterwards so the PATH updates. Verify:

```powershell
terraform version
az version
```

---

## 1. Log in to Azure

```powershell
az login
az account list --output table          # find the subscription you want
az account set --subscription "<SUBSCRIPTION_ID>"
az account show --query id -o tsv       # copy this id, you'll need it
```

---

## 2. (Manual) Request Azure OpenAI access — do this FIRST, it can take time

Azure OpenAI is gated. On many student/personal subscriptions it is **not
approved** and you cannot create the resource.

- Open the Azure Portal → search **Azure OpenAI** → "Create".
- If it lets you create one, you're approved. Good.
- If it shows an access-request form, fill it in. Approval can take hours/days.

**If you are not approved in time:** set `enable_openai = false` in
`terraform.tfvars`. The Functions will use the rule-based tagging fallback, which
the brief explicitly allows. You lose no points for this — the AI-tagging criteria
accepts a fallback.

> **Full step-by-step for this is in [OPENAI_SETUP.md](OPENAI_SETUP.md)** —
> access check, quota, model deployment, verification, wiring, and the plain-OpenAI
> / rule-based fallbacks. Read that for the detail; this is just the summary.

---

## 3. (Manual) Bootstrap the Terraform remote-state storage

Terraform needs somewhere to store its state. We do this one bit by hand because
it's the chicken-and-egg resource. Pick a globally-unique storage name.

```powershell
$RG="rg-tfstate"
$LOC="francecentral"
$SA="sttfstate" + -join ((48..57)+(97..122) | Get-Random -Count 6 | % {[char]$_})

az group create --name $RG --location $LOC
az storage account create --name $SA --resource-group $RG --location $LOC --sku Standard_LRS --encryption-services blob
az storage container create --name tfstate --account-name $SA --auth-mode login

Write-Host "Put this storage account name into terraform/versions.tf -> backend -> storage_account_name:"
Write-Host $SA
```

Then open [terraform/versions.tf](terraform/versions.tf) and paste `$SA` into the
empty `storage_account_name = ""`.

> Shortcut: if you don't care about remote state (solo project), just **delete or
> comment out** the whole `backend "azurerm"` block in `versions.tf` and skip this
> step — Terraform will use a local `terraform.tfstate` file. Simpler for grading.

---

## 4. (Manual) Create the service principal for GitHub Actions (OIDC)

The pipeline logs into Azure without a stored password using **federated
credentials**. Create an app registration and link it to your GitHub repo.

```powershell
# Replace these two:
$GH_ORG_REPO = "AugustinMoquin/projet_final_azure"   # e.g. augustinmqn/projet-azure
$SUB_ID = az account show --query id -o tsv

# Create the app + service principal
$APP_ID = az ad app create --display-name "gh-projet-azure" --query appId -o tsv
az ad sp create --id $APP_ID
$TENANT_ID = az account show --query tenantId -o tsv

# Give it rights on the subscription (Contributor is fine for a student project)
az role assignment create --assignee $APP_ID --role "Contributor" --scope "/subscriptions/$SUB_ID"

# Federated credential: trust GitHub Actions on the main branch.
# NOTE: PowerShell mangles inline JSON passed to az. Write it to a file instead.
@{
  name      = "github-main"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:$($GH_ORG_REPO):ref:refs/heads/main"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json | Out-File -FilePath fic.json -Encoding ascii

az ad app federated-credential create --id $APP_ID --parameters fic.json
Remove-Item fic.json

Write-Host "AZURE_CLIENT_ID       = $APP_ID"
Write-Host "AZURE_TENANT_ID       = $TENANT_ID"
Write-Host "AZURE_SUBSCRIPTION_ID = $SUB_ID"
```

Keep those three values — they go into GitHub secrets in step 7.

---

## 5. Run Terraform

```powershell
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set subscription_id, and enable_openai if needed

terraform init
terraform plan
terraform apply          # type 'yes'
```

When it finishes, capture the outputs you'll need:

```powershell
terraform output                         # human-readable summary
terraform output -raw function_app_name  # -> AZURE_FUNCTION_APP_NAME secret
terraform output -raw cosmos_primary_key # sensitive values need -raw
```

---

## 6. (Manual) Enable the static website on the docs storage account

Hosting the React build as a static website is a single account-level toggle that
the AzureRM provider doesn't expose cleanly, so flip it by hand:

```powershell
$SA = terraform output -raw docs_storage_account   # run inside terraform/
az storage blob service-properties update `
  --account-name $SA `
  --static-website `
  --index-document index.html `
  --404-document index.html

# Get the public URL of your frontend:
az storage account show -n $SA --query "primaryEndpoints.web" -o tsv
```

That URL is your `FUNCTION_BASE_URL`/frontend address. The pipeline uploads the
React build into the `$web` container of this same account.

---

## 7. (Manual) Set GitHub repository secrets & variables

Push this folder to a new GitHub repo first:

```powershell
cd ..                       # back to the project root
git init
git add .
git commit -m "Initial: terraform infra + pipeline"
gh repo create projet-azure --private --source=. --push   # or create via the UI
```

Then add the secrets. Using the `gh` CLI (run from the repo root):

```powershell
gh secret set AZURE_CLIENT_ID        --body "<from step 4>"
gh secret set AZURE_TENANT_ID        --body "<from step 4>"
gh secret set AZURE_SUBSCRIPTION_ID  --body "<from step 4>"
gh secret set AZURE_FUNCTION_APP_NAME --body "$(cd terraform; terraform output -raw function_app_name)"
gh secret set AZURE_WEB_STORAGE_ACCOUNT --body "$(cd terraform; terraform output -raw docs_storage_account)"

# Non-secret config the frontend build reads:
gh variable set FUNCTION_BASE_URL --body "https://<function_app_default_hostname>/api"
```

Or via the UI: **Repo → Settings → Secrets and variables → Actions**.

| Secret name               | Where it comes from                                  |
|---------------------------|------------------------------------------------------|
| `AZURE_CLIENT_ID`         | step 4                                                |
| `AZURE_TENANT_ID`         | step 4                                                |
| `AZURE_SUBSCRIPTION_ID`   | step 4                                                |
| `AZURE_FUNCTION_APP_NAME` | `terraform output -raw function_app_name`             |
| `AZURE_WEB_STORAGE_ACCOUNT` | `terraform output -raw docs_storage_account`        |

> The grading wants `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`,
> `AZURE_SUBSCRIPTION_ID`, `AZURE_FUNCTION_APP_NAME` "plus service-specific
> credentials". We avoid `AZURE_CLIENT_SECRET` by using OIDC (more secure). The
> Cosmos/Service Bus/SignalR/OpenAI credentials are **not** GitHub secrets — they
> live as Function App app settings, injected by Terraform (see
> `terraform/functions.tf`). That's intentional and worth saying in your README.

---

## 8. Deploy via the pipeline

The first push to `main` already triggered the workflow. Re-run any time from
**Actions → deploy → Run workflow**, or:

```powershell
git commit --allow-empty -m "trigger pipeline"
git push
```

Watch it: `gh run watch`.

---

## 9. (Manual) Smoke test the whole pipeline

1. Upload a file to the `documents` container:
   ```powershell
   $SA = (cd terraform; terraform output -raw docs_storage_account)
   az storage blob upload --account-name $SA --auth-mode login `
     --container-name documents --name test.pdf --file .\some-file.pdf
   ```
2. In the Portal → your Service Bus → `documents-queue`: a message appears.
3. Cosmos DB → Data Explorer → `documentsdb/documents`: a document appears and
   its status moves `UPLOADED → QUEUED → PROCESSING → PROCESSED`, with tags.
4. Application Insights → Logs (`traces`): you see entries with `correlationId`
   and `documentId`.
5. To exercise the **DLQ**: push a malformed message so processing fails 5×; it
   lands in `documents-queue/$DeadLetterQueue`, the DLQ Function marks the doc
   `ERROR`, and the React app gets the error notification.

---

## 10. Tear down (after the presentation, to avoid charges)

```powershell
cd terraform
terraform destroy
# then remove the bootstrap state RG if you made one:
az group delete --name rg-tfstate --yes
```

---

## What Terraform does vs. what you do manually

| Done by Terraform                         | Done manually (this file)                |
|-------------------------------------------|------------------------------------------|
| Resource group                            | Install tools, `az login`                |
| Blob storage + `documents` container      | Request Azure OpenAI access (step 2)     |
| Service Bus namespace, queue, DLQ config  | Bootstrap tfstate storage (step 3)       |
| Cosmos DB account / db / container        | Create service principal + OIDC (step 4) |
| SignalR (serverless)                      | Enable static website toggle (step 6)    |
| Log Analytics + App Insights              | Set GitHub secrets/variables (step 7)    |
| Function App + all app settings wired     | Push code, smoke test (8–9)              |
| Azure OpenAI account + model deployment   |                                          |
