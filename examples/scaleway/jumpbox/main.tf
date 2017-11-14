variable "name" { type = "string" }
variable "image_id" {}
variable "type" {
    type = "string"
    default = "VC1M"
}
variable "security_group_id" {
    type = "string"
    default = ""
}
variable "ssh_private_key_data" {}
variable "region" {}

resource "scaleway_server" "node" {
  name  = "${var.name}"
  image = "${var.image_id}"
  type  = "${var.type}"
  dynamic_ip_required = true
  security_group = "${var.security_group_id}"
  state = "running"

  volume {
    size_in_gb = 50
    type       = "l_ssd"
  }

  provisioner "local-exec" {
    command = "${path.root}/script/local-init.sh"
  }

  provisioner "file" {
    source      = "${path.root}/kon_id_rsa"
    destination = "/root/.ssh/id_rsa"

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.ssh_private_key_data}"
    }
  }

  provisioner "remote-exec" {
    inline      = [
        "chmod 600 /root/.ssh/id_rsa"
    ]

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.ssh_private_key_data}"
    }
  }

  provisioner "file" {
    source      = "${path.root}/script/jumpbox-provision.sh"
    destination = "/root/jumpbox-provision.sh"

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.ssh_private_key_data}"
    }
  }

  provisioner "remote-exec" {
    inline      = [
        "chmod +x /root/jumpbox-provision.sh",
        "./jumpbox-provision.sh"
    ]

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.ssh_private_key_data}"
    }
  }
}

output "id" {
    value = "${scaleway_server.node.id}"
}

output "ip" {
    value = "${scaleway_server.node.public_ip}"
}
