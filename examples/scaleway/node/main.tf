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
variable "jumpbox" {}
variable "jumpbox_ip" {}
variable "tinc_ip" {}
variable "region" {}

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
    command = "${path.root}/script/local-init.sh"
  }

  provisioner "local-exec" {
    command = "sleep 60"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} cp --gateway=${var.jumpbox} ${path.root}/kon_id_rsa.pub ${scaleway_server.node.id}:/root/"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} cp --gateway=${var.jumpbox} ${path.root}/script/node-provision.sh ${scaleway_server.node.id}:/root/"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec --gateway=${var.jumpbox} ${scaleway_server.node.id} 'cat kon_id_rsa.pub >> /root/.ssh/instance_keys && cat kon_id_rsa.pub >> /root/.ssh/authorized_keys'"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec ${var.jumpbox} 'ssh-keyscan -H ${scaleway_server.node.private_ip} >> ~/.ssh/known_hosts && tinc-net/add-server.sh ${scaleway_server.node.private_ip} eth0 ${var.tinc_ip} ${var.name}'"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec ${var.jumpbox} 'echo ${var.tinc_ip}   ${var.name} >> /etc/hosts && ssh-keyscan -H ${var.name} >> ~/.ssh/known_hosts'"
  }

  provisioner "local-exec" {
      command = "scw --region=${var.region} exec --gateway=${var.jumpbox} ${scaleway_server.node.id} './node-provision.sh'"
  }
}

output "id" {
    value = "${scaleway_server.node.id}"
}

output "ip" {
    value = "${scaleway_server.node.private_ip}"
}
