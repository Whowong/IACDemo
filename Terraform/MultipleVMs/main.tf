provider "azurerm" {
  version = "= 2.99"
  features {}
  use_msal = false
}

variable "numInstances" {
  type        = number
  default     = 25
  description = "Number of VMs"
}

terraform{
  backend "azurerm" {
  resource_group_name  = "AH_SharedServices"
  storage_account_name = "ahcsaiacterraform"
  container_name       = "terraform"
  key                  = "multiplevms.tfstate"
 }  
}

data "azurerm_key_vault" "akv" {
  name                = "AHCSAIACDemo"
  resource_group_name = "AH_SharedServices"
}

data "azurerm_key_vault_secret" "vmadminpassword" {
  name         = "vmadminpassword"
  key_vault_id = data.azurerm_key_vault.akv.id
}

resource "azurerm_resource_group" "rg" {
  name = "rg-IACDemoTFMultipleVMs"
  location = "eastus2"
}

resource "azurerm_virtual_network" "vnet" {
  name = "vnet-IACDemoTFMultipleVMs"
  address_space = ["10.0.0.0/16"]
  location = "eastus2"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "frontendsubnet" {
  name = "snet-IACDemoTFMultipleVMsFrontend"
  resource_group_name =  azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = ["10.0.1.0/24"]
}


resource "azurerm_network_interface" "vm1nic" {
  count = var.numInstances
  name = "nic-IACDemoTFMultipleVMs${count.index}"
  location = "eastus2"
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name = "ipconfig1"
    subnet_id = azurerm_subnet.frontendsubnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_recovery_services_vault" "recoveryvault" {
  name                = "tfex-recovery-vault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  soft_delete_enabled = false
}

resource "azurerm_backup_policy_vm" "backuppolicy" {

  name                = "tfex-recovery-vault-policy"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.recoveryvault.name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 10
  }
}

resource "azurerm_backup_protected_vm" "vm1" {
  count               = var.numInstances
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.recoveryvault.name
  source_vm_id        = azurerm_linux_virtual_machine.vm[count.index].id
  backup_policy_id    = azurerm_backup_policy_vm.backuppolicy.id
  depends_on = [
    azurerm_linux_virtual_machine.vm
  ]
}
resource "azurerm_linux_virtual_machine" "vm" {
  count                 = var.numInstances
  name                  = "vm-IACDemoTFMultipleVMs${count.index}"  
  location              = "eastus2"
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [element(azurerm_network_interface.vm1nic.*.id, count.index)]
  size                  = "Standard_F2"
  admin_username        = "adminuser"
  admin_password        = "${data.azurerm_key_vault_secret.vmadminpassword.value}"
  disable_password_authentication  = false

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  os_disk {
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  tags = {
    environment = "dev"
    department  = "finance"
    product     = "Terraform"
    test        = "true"
  }
}