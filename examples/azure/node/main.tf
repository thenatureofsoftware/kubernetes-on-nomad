variable "name" {}
variable "resource_group_name" {}
variable "location" {}
variable "vm_size" {}
variable "storage_account_name_endpoint" {}
variable "storage_container_name" {}
variable "ssh_key_path" {}
variable "ssh_key_data" {}
variable "subnet_id" {}
variable "private_ip_address" {}
variable "public_ip_address_id" {}

resource "azurerm_network_interface" "nic" {
    name                      = "${var.name}-nic"
    location                  = "${var.location}"
    resource_group_name       = "${var.resource_group_name}"
    internal_dns_name_label   = "${var.name}"

  ip_configuration {
    name                            = "${var.name}"
    subnet_id                       = "${var.subnet_id}"
    private_ip_address_allocation   = "static"
    private_ip_address              = "${var.private_ip_address}"
    public_ip_address_id            = "${var.public_ip_address_id}"
  }
}

resource "azurerm_virtual_machine" "core" {
  name                  = "${var.name}"
  location              = "${var.location}"
  resource_group_name   = "${var.resource_group_name}"
  network_interface_ids = ["${azurerm_network_interface.nic.id}"]
  vm_size               = "${var.vm_size}"
  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "CoreOS"
    offer     = "CoreOS"
    sku       = "Stable"
    version   = "latest"
  }

  storage_os_disk {
    name          = "osdisk1"
    vhd_uri       = "${var.storage_account_name_endpoint}${var.storage_container_name}/${var.name}-osdisk0.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  # Optional data disks
  storage_data_disk {
    name          = "datadisk0"
    vhd_uri       = "${var.storage_account_name_endpoint}${var.storage_container_name}/${var.name}-datadisk0.vhd"
    disk_size_gb  = "1023"
    create_option = "Empty"
    lun           = 0
  }

  os_profile {
    computer_name  = "${var.name}"
    admin_username = "core"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys = [{
        path     = "${var.ssh_key_path}"
        key_data = "${var.ssh_key_data}"
      }]
  }

  provisioner "local-exec" {
    command = "${path.root}/script/ssh-keygen.sh"
  }
}