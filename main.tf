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

# Check if Resource Group already exists
data "azurerm_resource_group" "existing_rg" {
  count = 1
  name  = "Partfiniti-AI"

  lifecycle {
    postcondition {
      condition     = self.location != null || self.location == null
      error_message = "Resource group lookup failed"
    }
  }
}

# Create Resource Group only if it doesn't exist
resource "azurerm_resource_group" "rg" {
  count    = try(data.azurerm_resource_group.existing_rg[0].id, null) != null ? 0 : 1
  name     = "Partfiniti-AI"
  location = "australiaeast"

  lifecycle {
    prevent_destroy = false  # Changed to allow deletion
  }
}

# Local value to use the existing or new RG
locals {
  resource_group_name     = try(data.azurerm_resource_group.existing_rg[0].name, azurerm_resource_group.rg[0].name)
  resource_group_location = try(data.azurerm_resource_group.existing_rg[0].location, azurerm_resource_group.rg[0].location)
}

# Key Vault
resource "azurerm_key_vault" "kv" {
  name                = "partfiniti-kv-${random_string.kv_suffix.result}"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

resource "random_string" "kv_suffix" {
  length  = 6
  upper   = false
  special = false
}

# Key Vault Access Policy for Service Principal
resource "azurerm_key_vault_access_policy" "policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
}

# Store SSH Private Key in Key Vault
resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "vm-ssh-private-key"
  value        = tls_private_key.ssh.private_key_pem
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.policy]
}

# Store SSH Public Key in Key Vault
resource "azurerm_key_vault_secret" "ssh_public_key" {
  name         = "vm-ssh-public-key"
  value        = tls_private_key.ssh.public_key_openssh
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.policy]
}

# Application Secret
resource "azurerm_key_vault_secret" "app_secret" {
  name         = "app-secret"
  value        = "super-secret-value"
  key_vault_id = azurerm_key_vault.kv.id

  depends_on = [azurerm_key_vault_access_policy.policy]
}

# Generate SSH Key Pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "Partfiniti-AI-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "LLM-staging-nsg"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

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

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Public IP
resource "azurerm_public_ip" "pip" {
  name                = "LLM-staging-ip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]
}

# Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "llm-staging-nic"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Associate NSG to NIC
resource "azurerm_network_interface_security_group_association" "nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "LLM-staging"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  size                = "Standard_D4s_v3"
  zone                = "1"
  admin_username      = "azureuser"

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    name                 = "LLM-staging_OsDisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # Enable secure boot and vTPM
  secure_boot_enabled = true
  vtpm_enabled        = true
}

# Grant VM access to Key Vault
resource "azurerm_key_vault_access_policy" "vm_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = azurerm_linux_virtual_machine.vm.identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.vm.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# Outputs
output "resource_group_name" {
  value       = local.resource_group_name
  description = "The name of the resource group"
}

output "resource_group_location" {
  value       = local.resource_group_location
  description = "The location of the resource group"
}

output "vm_name" {
  value       = azurerm_linux_virtual_machine.vm.name
  description = "The name of the virtual machine"
}

output "vm_public_ip" {
  value       = azurerm_public_ip.pip.ip_address
  description = "The public IP address of the VM"
}

output "vm_private_ip" {
  value       = azurerm_network_interface.nic.private_ip_address
  description = "The private IP address of the VM"
}

output "ssh_command" {
  value       = "ssh -i ~/.ssh/llm_staging_key azureuser@${azurerm_public_ip.pip.ip_address}"
  description = "SSH command to connect to the VM"
}

output "key_vault_name" {
  value       = azurerm_key_vault.kv.name
  description = "The name of the Key Vault"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "The URI of the Key Vault"
}

output "vm_identity_principal_id" {
  value       = azurerm_linux_virtual_machine.vm.identity[0].principal_id
  description = "The principal ID of the VM's managed identity"
}

output "ssh_private_key_secret_name" {
  value       = azurerm_key_vault_secret.ssh_private_key.name
  description = "The Key Vault secret name for SSH private key"
}

output "vm_id" {
  value       = azurerm_linux_virtual_machine.vm.id
  description = "The ID of the virtual machine"
}