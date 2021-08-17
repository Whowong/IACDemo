provider "azurerm" {
  version = "= 2.0.0"
  features {}
}

variable "numInstances" {
  type        = number
  default     = 2
  description = "Number of VMs"
}

terraform{
  backend "azurerm" {
  resource_group_name  = "AH_SharedServices"
  storage_account_name = "ahcsaterraform"
  container_name       = "terraform"
  key                  = "multiplevms.tfstate"
 }  
}

data "azurerm_key_vault" "akv" {
  name                = "IACDemo"
  resource_group_name = "AH_SharedServices"
}

data "azurerm_key_vault_secret" "vmadminpassword" {
  name         = "vmadminpassword"
  key_vault_id = data.azurerm_key_vault.akv.id
}

resource "azurerm_resource_group" "rg" {
  name = "rg-IACDemoTFMultipleVMs"
  location = "westus2"
}

resource "azurerm_virtual_network" "vnet" {
  name = "vnet-IACDemoTFMultipleVMs"
  address_space = ["10.0.0.0/16"]
  location = "westus2"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "frontendsubnet" {
  name = "snet-IACDemoTFMultipleVMsFrontend"
  resource_group_name =  azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix = "10.0.1.0/24"
}


resource "azurerm_network_interface" "vm1nic" {
  count = var.numInstances
  name = "nic-IACDemoTFMultipleVMs${count.index}"
  location = "westus2"
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name = "ipconfig1"
    subnet_id = azurerm_subnet.frontendsubnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  count                 = var.numInstances
  name                  = "vm-IACDemoTFMultipleVMs${count.index}"  
  location              = "westus2"
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
    temporary   = "false"
  }
}