variable "location" {
  type = "string"
  default = "northeurope"
}

variable "ssh_key_path" {
  type    = "string"
  default = "/home/core/.ssh/authorized_keys"
}

variable "ssh_key_file" {
  type    = "string"
  default = "~/.ssh/id_rsa"
}

provider "azurerm" {}

resource "azurerm_resource_group" "konTraining" {
  name      = "konTraining"
  location  = "${var.location}"
}

resource "azurerm_virtual_network" "konNetwork" {
  name                = "konNet"
  address_space       = ["192.168.0.0/16"]
  location            = "${azurerm_resource_group.konTraining.location}"
  resource_group_name = "${azurerm_resource_group.konTraining.name}"
}

# create subnet
resource "azurerm_subnet" "konSubNet101" {
  name                  = "konSubNet101"
  resource_group_name   = "${azurerm_resource_group.konTraining.name}"
  virtual_network_name  = "${azurerm_virtual_network.konNetwork.name}"
  address_prefix        = "192.168.101.0/24"
}

resource "azurerm_public_ip" "konIP" {
  name                         = "konIP"
  location                     = "${azurerm_resource_group.konTraining.location}"
  resource_group_name          = "${azurerm_resource_group.konTraining.name}"
  public_ip_address_allocation = "static"
}

resource "azurerm_storage_account" "konSA" {
  name                     = "konsa"
  resource_group_name      = "${azurerm_resource_group.konTraining.name}"
  location                 = "${azurerm_resource_group.konTraining.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "konSC" {
  name                  = "vhds"
  resource_group_name   = "${azurerm_resource_group.konTraining.name}"
  storage_account_name  = "${azurerm_storage_account.konSA.name}"
  container_access_type = "private"
}

###############################################################################
# jump-box
###############################################################################
module "jump-box" {
  source = "./jump-box"
  name                  = "jump-box"
  resource_group_name   = "${azurerm_resource_group.konTraining.name}"
  location              = "${azurerm_resource_group.konTraining.location}"
  vm_size               = "Standard_A0"
  osdisk_vhd_uri        = "${azurerm_storage_account.konSA.primary_blob_endpoint}${azurerm_storage_container.konSC.name}/jump-box-osdisk0.vhd"
  datadisk_vhd_uri      = "${azurerm_storage_account.konSA.primary_blob_endpoint}${azurerm_storage_container.konSC.name}/jump-box-datadisk0.vhd"
  ssh_key_path          = "${var.ssh_key_path}"
  ssh_key_data          = "${file("${var.ssh_key_file}.pub")}"
  ssh_private_key_data  = "${file("${var.ssh_key_file}")}"
  subnet_id               = "${azurerm_subnet.konSubNet101.id}"
  private_ip_address      = "192.168.101.254"
  public_ip_address_id    = "${azurerm_public_ip.konIP.id}"
  public_ip_address    = "${azurerm_public_ip.konIP.ip_address}"
}

###############################################################################
# core-01 nomad server
###############################################################################
module "core-01" {
  source                        = "./node"
  name                          = "core-01"
  private_ip_address            = "192.168.101.101"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-02 nomad server
###############################################################################
module "core-02" {
  source                        = "./node"
  name                          = "core-02"
  private_ip_address            = "192.168.101.102"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-03 nomad server
###############################################################################
module "core-03" {
  source                        = "./node"
  name                          = "core-03"
  private_ip_address            = "192.168.101.103"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-04 etcd
###############################################################################
module "core-04" {
  source                        = "./node"
  name                          = "core-04"
  private_ip_address            = "192.168.101.104"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-05 etcd
###############################################################################
module "core-05" {
  source                        = "./node"
  name                          = "core-05"
  private_ip_address            = "192.168.101.105"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-06 etcd
###############################################################################
module "core-06" {
  source                        = "./node"
  name                          = "core-06"
  private_ip_address            = "192.168.101.106"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-07 minion
###############################################################################
module "core-07" {
  source                        = "./node"
  name                          = "core-07"
  private_ip_address            = "192.168.101.107"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-08 minion
###############################################################################
module "core-08" {
  source                        = "./node"
  name                          = "core-08"
  private_ip_address            = "192.168.101.108"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}

###############################################################################
# core-09 minion
###############################################################################
module "core-09" {
  source                        = "./node"
  name                          = "core-09"
  private_ip_address            = "192.168.101.109"
  resource_group_name           = "${azurerm_resource_group.konTraining.name}"
  location                      = "${azurerm_resource_group.konTraining.location}"
  vm_size                       = "Standard_D1"
  storage_account_name_endpoint = "${azurerm_storage_account.konSA.primary_blob_endpoint}"
  storage_container_name        = "${azurerm_storage_container.konSC.name}"
  ssh_key_path                  = "${var.ssh_key_path}"
  ssh_key_data                  = "${file("${path.root}/kon_id_rsa.pub")}"
  subnet_id                     = "${azurerm_subnet.konSubNet101.id}"
  public_ip_address_id          = ""
}
