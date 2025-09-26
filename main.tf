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
  count               = 1
  name                = "fastapi-vm-ip"
  resource_group_name = azurerm_resource_group.rg.name

  # Handle case where resource doesn't exist
  lifecycle {
    postcondition {
      condition     = self.ip_address != null || self.ip_address == null
      error_message = "Public IP lookup failed"
    }
  }
}

# Create Public IP only if it does not exist
resource "azurerm_public_ip" "pip" {
  count               = try(data.azurerm_public_ip.existing_pip[0].id, null) != null ? 0 : 1
  name                = "fastapi-vm-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Local value to determine which IP to use
locals {
  public_ip_id = try(data.azurerm_public_ip.existing_pip[0].id, azurerm_public_ip.pip[0].id)
  public_ip_address = try(data.azurerm_public_ip.existing_pip[0].ip_address, azurerm_public_ip.pip[0].ip_address)
}

# Virtual Network
# Try to fetch existing VNet
data "azurerm_virtual_network" "existing_vnet" {
  count               = 1
  name                = "fastapi-vnet-test"
  resource_group_name = azurerm_resource_group.rg.name

  # Handle case where resource doesn't exist
  lifecycle {
    postcondition {
      condition     = self.id != null || self.id == null
      error_message = "VNet lookup failed"
    }
  }
}

# Create new VNet only if it doesn't exist
resource "azurerm_virtual_network" "vnet" {
  count               = try(data.azurerm_virtual_network.existing_vnet[0].id, null) != null ? 0 : 1
  name                = "fastapi-vnet-test"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Local values to determine which VNet to use
locals {
  vnet_name = try(data.azurerm_virtual_network.existing_vnet[0].name, azurerm_virtual_network.vnet[0].name)
  vnet_id   = try(data.azurerm_virtual_network.existing_vnet[0].id, azurerm_virtual_network.vnet[0].id)
}

# Network Security Group and rule
resource "azurerm_network_security_group" "nsg" {
  name                = "fastapi-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "fastapi-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = local.vnet_name
  address_prefixes     = ["10.0.1.0/24"]
}

# Associate Network Security Group to Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
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
    public_ip_address_id          = local.public_ip_id
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

# Grant VM Reader role at subscription level for managed identity access
resource "azurerm_role_assignment" "vm_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_virtual_machine.vm.identity[0].principal_id
}

# Outputs
output "public_ip" {
  value = local.public_ip_address
}

output "vnet_name" {
  value = local.vnet_name
}

output "vnet_id" {
  value = local.vnet_id
}

output "vm_public_ip" {
  value = local.public_ip_address
}

output "ssh_command" {
  value = "ssh azureuser@${local.public_ip_address}"
}