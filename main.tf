terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "fastapi-rg"
  location = "East Asia"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_service_plan" "plan" {
  name                = "fastapi-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "B1"
  os_type             = "Linux"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_key_vault" "kv" {
  name                = "fastapikv123"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
}

resource "azurerm_key_vault_access_policy" "policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set"]
}

resource "azurerm_key_vault_secret" "new_secret" {
  name         = "new-secret"
  value        = "super-secret-value"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.policy]
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_linux_web_app" "app" {
  name                = "fastapi-app-service-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  service_plan_id     = azurerm_service_plan.plan.id

  site_config {
    application_stack {
      python_version = "3.9"
    }

    app_command_line = "python -m uvicorn main:app --host 0.0.0.0 --port 8002"
  }

  app_settings = {
    "WEBSITES_PORT"                    = "8000"
    "MY_SECRET"                       = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.new_secret.id})"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_ORYX_BUILD"              = "true"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Grant the App Service access to Key Vault
resource "azurerm_key_vault_access_policy" "app_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = azurerm_linux_web_app.app.identity[0].tenant_id
  object_id    = azurerm_linux_web_app.app.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# Public IP
# Try to fetch existing Public IP
data "azurerm_public_ip" "existing_pip" {
  name                = "fastapi-vm-ip"
  resource_group_name = azurerm_resource_group.rg.name
}

# Create Public IP only if it does not exist
resource "azurerm_public_ip" "pip" {
  count               = try(length(data.azurerm_public_ip.existing_pip.id), 0) == 0 ? 1 : 0
  name                = "fastapi-vm-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Unified reference (use existing if available, otherwise new)
output "public_ip" {
  value = coalesce(
    try(data.azurerm_public_ip.existing_pip.ip_address, null),
    try(azurerm_public_ip.pip[0].ip_address, null)
  )
}


# Virtual Network
# Try to fetch existing VNet
data "azurerm_virtual_network" "existing_vnet" {
  name                = "fastapi-vnet-test"
  resource_group_name = azurerm_resource_group.rg.name
}

# Create new VNet only if it doesn't exist
resource "azurerm_virtual_network" "vnet" {
  count               = try(length(data.azurerm_virtual_network.existing_vnet.id), 0) == 0 ? 1 : 0
  name                = "fastapi-vnet-test"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Unified reference (works whether it exists already or was created)
output "vnet_name" {
  value = coalesce(
    try(data.azurerm_virtual_network.existing_vnet.name, null),
    try(azurerm_virtual_network.vnet[0].name, null)
  )
}

output "vnet_id" {
  value = coalesce(
    try(data.azurerm_virtual_network.existing_vnet.id, null),
    try(azurerm_virtual_network.vnet[0].id, null)
  )
}


# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "fastapi-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# NIC
resource "azurerm_network_interface" "nic" {
  name                = "fastapi-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}


# Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "terraform-test"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "azureuser"

  # Disable password authentication
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub") # You'll need to create this
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Grant VM access to Key Vault
resource "azurerm_key_vault_access_policy" "vm_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = azurerm_linux_virtual_machine.vm.identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.vm.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

output "vm_public_ip" {
  value = azurerm_public_ip[count.index].pip.ip_address
}

output "ssh_command" {
  value = "ssh azureuser@${azurerm_public_ip[count.index].pip.ip_address}"
}
