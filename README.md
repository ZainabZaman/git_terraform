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

3. **Configure Azure Credentials**
   - Add your Azure credentials as a secret named `AZURE_CREDENTIALS` in your GitHub repository settings.

4. **Usage**
   - The workflow will clean up resources, deploy infrastructure using Terraform, and provide SSH connection instructions as artifacts.

5. **Troubleshooting**
   - If you see an Application Error after deployment, check your Azure App Service logs and ensure your application is correctly configured and running.

---

**Remember to update all placeholders before running the workflow!**
