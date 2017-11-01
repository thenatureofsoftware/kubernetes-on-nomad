variable "name" {}
variable "resource_group_name" {}
variable "location" {}
variable "vm_size" {}
variable "osdisk_vhd_uri" {}
variable "datadisk_vhd_uri" {}
variable "ssh_key_path" {}
variable "ssh_key_data" {}
variable "ssh_private_key_data" {}
variable "subnet_id" {}
variable "private_ip_address" {}
variable "public_ip_address_id" {}
variable "public_ip_address" {}

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

resource "azurerm_virtual_machine" "jump-box" {
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
    name          = "osdisk0"
    vhd_uri = "${var.osdisk_vhd_uri}"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  # Optional data disks
  storage_data_disk {
    name          = "datadisk0"
    vhd_uri       = "${var.datadisk_vhd_uri}"
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

  provisioner "file" {
    source      = "${path.root}/kon_id_rsa"
    destination = "/home/core/.ssh/id_rsa"

    connection {
        type     = "ssh"
        user     = "core"
        host    = "${var.public_ip_address}"
        private_key = "${var.ssh_private_key_data}"
    }
  }

  provisioner "remote-exec" {
    inline      = [
        "chmod 600 ~/.ssh/id_rsa"
    ]

    connection {
        type     = "ssh"
        user     = "core"
        host    = "${var.public_ip_address}"
        private_key = "${var.ssh_private_key_data}"
    }
  }
}
