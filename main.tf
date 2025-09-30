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

# Resource Group - will be created if it doesn't exist
resource "azurerm_resource_group" "rg" {
  name     = "setup-infra"
  location = "East Asia"

  lifecycle {
    prevent_destroy = false
  }
}

# Key Vault - will be created if it doesn't exist
resource "azurerm_key_vault" "kv" {
  name                = "fastapikv123"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Enable soft delete and purge protection for production
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  lifecycle {
    prevent_destroy = false
  }
}

# Key Vault Access Policy for Service Principal
resource "azurerm_key_vault_access_policy" "policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
  key_permissions    = ["Get", "List", "Create", "Delete"]
}

# Network Security Group
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

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "fastapi-vnet-test"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "fastapi-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Associate Network Security Group to Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Public IP
resource "azurerm_public_ip" "pip" {
  name                = "fastapi-vm-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Interface
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
    public_key = file("~/.ssh/id_rsa.pub")
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

# Outputs - Return credentials instead of deploying app
output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "Name of the resource group"
}

output "resource_group_location" {
  value       = azurerm_resource_group.rg.location
  description = "Location of the resource group"
}

output "key_vault_name" {
  value       = azurerm_key_vault.kv.name
  description = "Name of the Key Vault"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "URI of the Key Vault"
}

output "key_vault_id" {
  value       = azurerm_key_vault.kv.id
  description = "Resource ID of the Key Vault"
}

output "vm_public_ip" {
  value       = azurerm_public_ip.pip.ip_address
  description = "Public IP address of the VM"
}

output "vm_name" {
  value       = azurerm_linux_virtual_machine.vm.name
  description = "Name of the virtual machine"
}

output "vm_id" {
  value       = azurerm_linux_virtual_machine.vm.id
  description = "Resource ID of the virtual machine"
}

output "vm_principal_id" {
  value       = azurerm_linux_virtual_machine.vm.identity[0].principal_id
  description = "Managed Identity Principal ID of the VM"
}

output "ssh_command" {
  value       = "ssh -i ssh_private_key.pem azureuser@${azurerm_public_ip.pip.ip_address}"
  description = "SSH command to connect to the VM"
}

output "connection_instructions" {
  value = <<-EOT
    To connect to your VM:
    1. Download the SSH private key from GitHub Actions artifacts
    2. Set correct permissions: chmod 600 ssh_private_key.pem
    3. Connect using: ssh -i ssh_private_key.pem azureuser@${azurerm_public_ip.pip.ip_address}

    To access Key Vault:
    - Vault Name: ${azurerm_key_vault.kv.name}
    - Vault URI: ${azurerm_key_vault.kv.vault_uri}
    - Use Azure CLI: az keyvault secret show --vault-name ${azurerm_key_vault.kv.name} --name <secret-name>
  EOT
  description = "Instructions for connecting to resources"
}