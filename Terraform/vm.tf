# ─────────────────────────────────────────────────────────────────────────────
# Provider
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}

  # Free tier subscriptions sometimes need this to skip provider registration
  # errors on first run
  skip_provider_registration = false
}

# ─────────────────────────────────────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-vm-day04"
}

variable "location" {
  description = <<EOT
Azure region. Free tier works best in eastus or eastus2.
DO NOT use westeurope or northeurope — B1s capacity is
almost always exhausted there for free tier subscriptions.
EOT
  type    = string
  default = "eastus"
}

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "vm-day04"
}

variable "vm_size" {
  description = <<EOT
Azure free tier eligible VM size.
Standard_B1s is the free tier VM (750 hrs/month free).
If B1s is unavailable in your region, try Standard_B1ms.
DO NOT use B2s or larger — not covered by free tier.
EOT
  type    = string
  default = "Standard_B1s"
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "azureuser"
}

variable "admin_password" {
  description = "Admin password for the VM (min 12 chars, upper+lower+number+special)"
  type        = string
  sensitive   = true
}

variable "os_disk_size_gb" {
  description = <<EOT
OS disk size in GB.
Free tier includes 2 x 64 GB managed disks.
Keep at 30 GB to stay within free tier limits.
EOT
  type    = number
  default = 30
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# ─────────────────────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.vm_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_subnet" "main" {
  name                 = "subnet-${var.vm_name}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  depends_on = [azurerm_virtual_network.main]
}

resource "azurerm_public_ip" "main" {
  name                = "pip-${var.vm_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.vm_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_network_interface" "main" {
  name                = "nic-${var.vm_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }

  depends_on = [
    azurerm_subnet.main,
    azurerm_public_ip.main,
  ]
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id

  depends_on = [
    azurerm_network_interface.main,
    azurerm_network_security_group.main,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Virtual Machine
#
# FREE TIER LIMITS (per month):
#   ✅ 750 hrs  Standard_B1s Linux VM
#   ✅ 64 GB    managed disk (we use 30 GB)
#   ✅ 5 GB     outbound data transfer
#   ✅ 1        public IP (Standard SKU not free — see note below)
#
# ⚠️  NOTE ON PUBLIC IP COST:
#   Standard SKU public IPs are NOT free (~$0.005/hr).
#   To stay 100% free, delete the VM when not in use (destroy action),
#   or change allocation_method to "Dynamic" and sku to "Basic" above —
#   but Basic SKU is being retired by Azure in Sept 2025.
#   Standard is kept here for compatibility.
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "main" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size

  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.main.id
  ]

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # cheapest — included in free tier
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    environment = "day04"
    managed_by  = "terraform"
  }

  depends_on = [
    azurerm_network_interface_security_group_association.main,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "vm_name" {
  description = "Name of the created VM"
  value       = azurerm_linux_virtual_machine.main.name
}

output "public_ip_address" {
  description = "Public IP to SSH into the VM"
  value       = azurerm_public_ip.main.ip_address
}

output "ssh_command" {
  description = "Ready-to-use SSH command"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}

output "resource_group" {
  description = "Resource group containing all VM resources"
  value       = azurerm_resource_group.main.name
}

output "free_tier_reminder" {
  description = "Reminder to destroy when not in use"
  value       = "REMINDER: Run 'destroy' when done to avoid charges. Free tier = 750 hrs/month B1s."
}
