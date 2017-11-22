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
    description = "scaleway security group for this server"
    type        = "string"
    default     = ""
}
variable "region" {
    description = "Datacenter region (par1 or ams1)"
    type        = "string"
}
variable "jumpbox" {
    description = "jumpbox scaleway server ID"
    type        = "string"
}
variable "jumpbox_ip" {
    description = "jumpbox IP-address"
    type        = "string"
}
variable "tinc_ip" {
    description = "user defined IP-address in the IPv4 private address space"
    type        = "string"
}
variable "ssh_public_key_file" {
    description = "Path to ssh public key file (.ssh/id_rsa.pub)"
    type        = "string"
}

resource "scaleway_server" "node" {
  name  = "${var.name}"
  image = "${var.image_id}"
  type  = "${var.type}"
  dynamic_ip_required = false
  security_group = "${var.security_group_id}"
  state = "running"

  volume {
    size_in_gb = 50
    type       = "l_ssd"
  }

  provisioner "local-exec" {
    command = "sleep 60"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} cp --gateway=${var.jumpbox} ${var.ssh_public_key_file} ${scaleway_server.node.id}:/root/"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} cp --gateway=${var.jumpbox} ${path.module}/provision.sh ${scaleway_server.node.id}:/root/"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec --gateway=${var.jumpbox} ${scaleway_server.node.id} 'cat id_rsa.pub >> /root/.ssh/instance_keys && cat id_rsa.pub >> /root/.ssh/authorized_keys && rm -f id_rsa.pub'"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec ${var.jumpbox} 'ssh-keyscan -H ${scaleway_server.node.private_ip} >> ~/.ssh/known_hosts && tinc-net/add-server.sh ${scaleway_server.node.private_ip} eth0 ${var.tinc_ip} ${var.name}'"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec ${var.jumpbox} 'echo ${var.tinc_ip}   ${var.name} >> /etc/hosts && ssh-keyscan -H ${var.name} >> ~/.ssh/known_hosts'"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec --gateway=${var.jumpbox} ${scaleway_server.node.id} './provision.sh'"
  }
}

output "id" {
    value = "${scaleway_server.node.id}"
}

output "ip" {
    value = "${scaleway_server.node.private_ip}"
}
