# Azure VM Infrastructure Deployment

## Setup Instructions

1. **Update Branch Name**
   - In `.github/workflows/deploy.yml`, find:
     ```yaml
     branches: [ "<YOUR_BRANCH_NAME>" ]
     ```
   - Replace `<YOUR_BRANCH_NAME>` with the branch you want to trigger deployments from.

2. **Set Azure Subscription ID**
   - In `.github/workflows/deploy.yml` and `main.tf`, find all instances of:
     ```
     <YOUR_AZURE_SUBSCRIPTION_ID>
     ```
   - Replace `<YOUR_AZURE_SUBSCRIPTION_ID>` with your actual Azure Subscription ID.

   - In `main.tf`, update the following block:
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
   - Replace `<YOUR_GIT_REPO_URL>` with your actual repository URL.

4. **Configure Azure Credentials**
   - Add your Azure credentials as a secret named `AZURE_CREDENTIALS` in your GitHub repository settings.

5. **Usage**
   - The workflow will clean up resources, deploy infrastructure using Terraform, and provide SSH connection instructions as artifacts.

6. **Troubleshooting**
   - If you see an Application Error after deployment, check your Azure App Service logs and ensure your application is correctly configured and running.

---

**Remember to update all placeholders before running the workflow!**
