# Azure VM Infrastructure Deployment

## Setup Instructions

1. **Update Branch Name**
   - In `.github/workflows/deploy.yml`, find:
     ```yaml
     branches: [ "<YOUR_BRANCH_NAME>" ]
     ```
   - If exists then replace `<YOUR_BRANCH_NAME>` with the branch you want to trigger deployments from.

2. **Set Azure Subscription ID**
   - In `.github/workflows/deploy.yml` and `main.tf`, find all instances of:
     ```
     <YOUR_AZURE_SUBSCRIPTION_ID>
     ```
   - If exists then replace `<YOUR_AZURE_SUBSCRIPTION_ID>` with your actual Azure Subscription ID.

   - In `main.tf`, update the following block, if exists:
     ```hcl
     provider "azurerm" {
       features {}
       subscription_id = "<YOUR_AZURE_SUBSCRIPTION_ID>" # <-- UPDATE THIS TO YOUR AZURE SUBSCRIPTION ID
     }
     ```

3. **Set Git Repository URL**
   - In `.github/workflows/deploy.yml`, find:
     ```bash
     git clone <YOUR_GIT_REPO_URL> # <-- UPDATE THIS TO YOUR GIT REPO URL
     ```
   - If exists then replace `<YOUR_GIT_REPO_URL>` with your actual repository URL.

4. **Configure Azure Credentials**
   - Add your Azure credentials as a secret named `AZURE_CREDENTIALS` in your GitHub repository settings.

---

## Azure Authentication Setup

### 🔑 Step 1: Install Azure CLI

On your machine (Linux/macOS/Windows):

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash   # Ubuntu/Debian
# or follow https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
```

Login:

```bash
az login
```

This will open a browser → sign in with your Azure account.

### 🔑 Step 2: Get Subscription Info

```bash
az account show --output table
```

Take note of:
- `id` → subscriptionId
- `tenantId`

### 🔑 Step 3: Create a Service Principal (SP)

This creates a client identity for GitHub Actions to authenticate:

```bash
az ad sp create-for-rbac --name fastapi-sp --role contributor --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID> --sdk-auth
```

Replace `<YOUR_SUBSCRIPTION_ID>` with the one from step 2.

It will output JSON like this:

```json
{
  "clientId": "xxxx-xxxx-xxxx",
  "clientSecret": "xxxx-xxxx-xxxx",
  "subscriptionId": "xxxx-xxxx-xxxx",
  "tenantId": "xxxx-xxxx-xxxx",
  "activeDirectoryEndpointUrl": "...",
  "resourceManagerEndpointUrl": "...",
  "managementEndpointUrl": "...",
  "activeDirectoryGraphResourceId": "...",
  "sqlManagementEndpointUrl": "...",
  "galleryEndpointUrl": "...",
  "activeDirectoryGraphApiVersion": "..."
}
```

### 🔑 Step 4: Store in GitHub Secrets

Go to your repo → Settings → Secrets and variables → Actions → New repository secret.

- **Name:** `AZURE_CREDENTIALS`
- **Value:** paste the entire JSON above.

---

**Remember to update all placeholders before running the workflow!**
