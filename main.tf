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

# Variables for VM configurations
variable "dev_vm_name" {
  description = "Name for the development VM"
  type        = string
}

variable "dev_vm_size" {
  description = "Size for the development VM"
  type        = string
}

variable "dev_vm_location" {
  description = "Location for the development VM"
  type        = string
}

variable "staging_vm_name" {
  description = "Name for the staging VM"
  type        = string
}

variable "staging_vm_size" {
  description = "Size for the staging VM"
  type        = string
}

variable "staging_vm_location" {
  description = "Location for the staging VM"
  type        = string
}

# Local variables for environment configuration
locals {
  environments = {
    dev = {
      vm_name     = var.dev_vm_name
      vm_size     = var.dev_vm_size
      vm_location = var.dev_vm_location
      vnet_cidr   = "10.0.0.0/16"
      subnet_cidr = "10.0.1.0/24"
      ssh_key     = "~/.ssh/id_rsa_dev.pub"
    }
    staging = {
      vm_name     = var.staging_vm_name
      vm_size     = var.staging_vm_size
      vm_location = var.staging_vm_location
      vnet_cidr   = "10.1.0.0/16"
      subnet_cidr = "10.1.1.0/24"
      ssh_key     = "~/.ssh/id_rsa_staging.pub"
    }
  }
}

# Resource Group - Shared across all environments
resource "azurerm_resource_group" "rg" {
  name     = "setup-infra"
  location = "East Asia"

  lifecycle {
    prevent_destroy = false
  }
}

# Key Vault - Shared across all environments
resource "azurerm_key_vault" "kv" {
  name                = "setup-infra-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

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

# Network Security Groups for each environment
resource "azurerm_network_security_group" "nsg" {
  for_each = local.environments

  name                = "fastapi-nsg-${each.key}"
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

  tags = {
    Environment = each.key
  }
}

# Virtual Networks for each environment
resource "azurerm_virtual_network" "vnet" {
  for_each = local.environments

  name                = "fastapi-vnet-${each.key}"
  address_space       = [each.value.vnet_cidr]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    Environment = each.key
  }
}

# Subnets for each environment
resource "azurerm_subnet" "subnet" {
  for_each = local.environments

  name                 = "fastapi-subnet-${each.key}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[each.key].name
  address_prefixes     = [each.value.subnet_cidr]
}

# Associate Network Security Group to Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  for_each = local.environments

  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
}

# Public IPs for each environment
resource "azurerm_public_ip" "pip" {
  for_each = local.environments

  name                = "fastapi-vm-ip-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = each.key
  }
}

# Network Interfaces for each environment
resource "azurerm_network_interface" "nic" {
  for_each = local.environments

  name                = "fastapi-nic-${each.key}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet[each.key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[each.key].id
  }

  tags = {
    Environment = each.key
  }
}

# Virtual Machines for each environment
resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.environments

  name                = each.value.vm_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = each.value.vm_location
  size                = each.value.vm_size
  admin_username      = "azureuser"

  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.nic[each.key].id,
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(each.value.ssh_key)
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

  tags = {
    Environment = each.key
  }
}

# Grant VM access to Key Vault
resource "azurerm_key_vault_access_policy" "vm_policy" {
  for_each = local.environments

  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = azurerm_linux_virtual_machine.vm[each.key].identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.vm[each.key].identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# Outputs for all environments
output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "Name of the resource group"
}

output "key_vault_name" {
  value       = azurerm_key_vault.kv.name
  description = "Name of the Key Vault"
}

output "key_vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "URI of the Key Vault"
}

# Dev Environment Outputs
output "dev_vm_name" {
  value       = azurerm_linux_virtual_machine.vm["dev"].name
  description = "Name of the development VM"
}

output "dev_vm_public_ip" {
  value       = azurerm_public_ip.pip["dev"].ip_address
  description = "Public IP address of the development VM"
}

output "dev_vm_size" {
  value       = azurerm_linux_virtual_machine.vm["dev"].size
  description = "Size of the development VM"
}

output "dev_vm_location" {
  value       = azurerm_linux_virtual_machine.vm["dev"].location
  description = "Location of the development VM"
}

output "dev_ssh_command" {
  value       = "ssh -i dev_ssh_private_key.pem azureuser@${azurerm_public_ip.pip["dev"].ip_address}"
  description = "SSH command to connect to the development VM"
}

# Staging Environment Outputs
output "staging_vm_name" {
  value       = azurerm_linux_virtual_machine.vm["staging"].name
  description = "Name of the staging VM"
}

output "staging_vm_public_ip" {
  value       = azurerm_public_ip.pip["staging"].ip_address
  description = "Public IP address of the staging VM"
}

output "staging_vm_size" {
  value       = azurerm_linux_virtual_machine.vm["staging"].size
  description = "Size of the staging VM"
}

output "staging_vm_location" {
  value       = azurerm_linux_virtual_machine.vm["staging"].location
  description = "Location of the staging VM"
}

output "staging_ssh_command" {
  value       = "ssh -i staging_ssh_private_key.pem azureuser@${azurerm_public_ip.pip["staging"].ip_address}"
  description = "SSH command to connect to the staging VM"
}

# Summary output
output "deployment_summary" {
  value = {
    dev = {
      vm_name   = azurerm_linux_virtual_machine.vm["dev"].name
      vm_size   = azurerm_linux_virtual_machine.vm["dev"].size
      location  = azurerm_linux_virtual_machine.vm["dev"].location
      public_ip = azurerm_public_ip.pip["dev"].ip_address
      ssh_key   = "dev_ssh_private_key.pem"
    }
    staging = {
      vm_name   = azurerm_linux_virtual_machine.vm["staging"].name
      vm_size   = azurerm_linux_virtual_machine.vm["staging"].size
      location  = azurerm_linux_virtual_machine.vm["staging"].location
      public_ip = azurerm_public_ip.pip["staging"].ip_address
      ssh_key   = "staging_ssh_private_key.pem"
    }
  }
  description = "Summary of all deployed environments"
}