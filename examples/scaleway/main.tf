variable "region" {
  default = "par1"
}

provider "scaleway" {
    region = "${var.region}"
}

variable "ssh_key_file" {
  type    = "string"
  default = "~/.ssh/id_rsa"
}

variable "ssh_key_path" {
  type    = "string"
  default = "/root/.ssh/authorized_keys"
}

data "scaleway_image" "docker" {
  architecture = "x86_64"
  name         = "Docker"
}

###############################################################################
# jump-box
###############################################################################
module "jumpbox" {
    source                              = "./jumpbox"
    name                                = "jumpbox"
    region                              = "${var.region}"
    image_id                            = "${data.scaleway_image.docker.id}"
    provisioner_ssh_private_key_data    = "${file("${var.ssh_key_file}")}"
    ssh_private_key_file                = "${path.root}/.ssh/id_rsa"
    local-init-script                   = "${path.root}/key-gen.sh"
}

output "jumpbox.id" {
  value = "${module.jumpbox.id}"
}

output "jumpbox.ip" {
  value = "${module.jumpbox.ip}"
}

###############################################################################
# node01
###############################################################################
module "node01" {
    source                = "./node"
    name                  = "node01"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.101"
}

###############################################################################
# node02
###############################################################################
module "node02" {
    source                = "./node"
    name                  = "node02"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.102"
}

###############################################################################
# node03
###############################################################################
module "node03" {
    source                = "./node"
    name                  = "node03"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.103"
}

###############################################################################
# node04
###############################################################################
module "node04" {
    source                = "./node"
    name                  = "node04"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.104"
}

###############################################################################
# node05
###############################################################################
module "node05" {
    source                = "./node"
    name                  = "node05"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.105"
}

###############################################################################
# node06
###############################################################################
module "node06" {
    source                = "./node"
    name                  = "node06"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.106"
}

###############################################################################
# node07
###############################################################################
module "node07" {
    source                = "./node"
    name                  = "node07"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.107"
}

###############################################################################
# node08
###############################################################################
module "node08" {
    source                = "./node"
    name                  = "node08"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.108"
}

###############################################################################
# node09
###############################################################################
module "node09" {
    source                = "./node"
    name                  = "node09"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.109"
}

###############################################################################
# node10
###############################################################################
module "node10" {
    source                = "./node"
    name                  = "node10"
    region                = "${var.region}"
    image_id              = "${data.scaleway_image.docker.id}"
    jumpbox               = "${module.jumpbox.id}"
    jumpbox_ip            = "${module.jumpbox.ip}"
    ssh_public_key_file   = "${path.root}/.ssh/id_rsa.pub"
    tinc_ip               = "192.168.1.110"
}

output "node01.id" { value = "${module.node01.id}" }
output "node01.ip" { value = "${module.node01.ip}" }

output "node02.id" { value = "${module.node02.id}" }
output "node02.ip" { value = "${module.node02.ip}" }

output "node03.id" { value = "${module.node03.id}" }
output "node03.ip" { value = "${module.node03.ip}" }

output "node04.id" { value = "${module.node04.id}" }
output "node04.ip" { value = "${module.node04.ip}" }

output "node05.id" { value = "${module.node05.id}" }
output "node05.ip" { value = "${module.node05.ip}" }

output "node06.id" { value = "${module.node06.id}" }
output "node06.ip" { value = "${module.node06.ip}" }

output "node07.id" { value = "${module.node07.id}" }
output "node07.ip" { value = "${module.node07.ip}" }

output "node08.id" { value = "${module.node08.id}" }
output "node08.ip" { value = "${module.node08.ip}" }

output "node09.id" { value = "${module.node09.id}" }
output "node09.ip" { value = "${module.node09.ip}" }

output "node10.id" { value = "${module.node10.id}" }
output "node10.ip" { value = "${module.node10.ip}" }

