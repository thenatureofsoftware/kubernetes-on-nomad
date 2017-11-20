variable "name" {
    description = "Server name (hostname)"
    type        = "string"
}
variable "image_id" {
    description = "Server image"
    type        = "string"
}
variable "type" {
    description = "Server commercial-type, C1, C2[S|M|L], X64-[2|4|8|15|30|60|120]GB, ARM64-[2|4|8]GB"
    type        = "string"
    default     = "VC1M"
}
variable "security_group_id" {
    type = "string"
    default = ""
}
variable "region" {
    description = "Datacenter region (par1 or ams1)"
    type        = "string"
}
variable "ssh_private_key_file" {
    description = "Path to ssh private key file (.ssh/id_rsa)"
    type        = "string"
}
variable "provisioner_ssh_private_key_data" {
    description = "ssh key for provisioner connection"
    type        = "string"
}
variable "local-init-script" {
    description = "local executed provisioning script"
    type        = "string"
}

resource "scaleway_server" "node" {
  name  = "${var.name}"
  image = "${var.image_id}"
  type  = "${var.type}"
  dynamic_ip_required = true
  security_group = "${var.security_group_id}"
  state = "running"

  provisioner "local-exec" {
    command = "${var.local-init-script}"
  }

  provisioner "file" {
    source      = "${var.ssh_private_key_file}"
    destination = "/root/.ssh/id_rsa"

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.provisioner_ssh_private_key_data}"
    }
  }

  provisioner "remote-exec" {
    inline      = [
        "chmod 600 /root/.ssh/id_rsa"
    ]

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.provisioner_ssh_private_key_data}"
    }
  }

  provisioner "file" {
    source      = "${path.module}/provision.sh"
    destination = "/root/provision.sh"

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.provisioner_ssh_private_key_data}"
    }
  }

  provisioner "remote-exec" {
    inline      = [
        "chmod +x /root/provision.sh",
        "./provision.sh"
    ]

    connection {
        type     = "ssh"
        user     = "root"
        private_key = "${var.provisioner_ssh_private_key_data}"
    }
  }
}

output "id" {
    value = "${scaleway_server.node.id}"
}

output "ip" {
    value = "${scaleway_server.node.public_ip}"
}
