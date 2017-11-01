job "kube-proxy" {
  region = "global"
  datacenters = ["dc1"]
  type = "system"

  group "kube-proxy-grp" {
    count = 1

    task "kube-proxy" {
      driver = "docker"

      template {
        destination = "local/kube-proxy.env"
        env         = true
        data      = <<EOH
CLUSTER_CIDR={{key "kubernetes/network/pod-network-cidr"}}
K8S_VERSION={{key "kubernetes/version"}}
EOH
      }

      template {
        destination = "local/kubernetes/kubeconfig.conf"
        data      = <<EOF
{{key "kubernetes/admin/kubeconfig" }}
EOF
      }

      config {
        image = "gcr.io/google_containers/kube-proxy-amd64:${K8S_VERSION}"
        network_mode = "host"
        privileged = true
        
        volumes = [
          "local/kubernetes:/etc/kubernetes",
          "/var/lib/kube-proxy:/var/lib/kube-proxy",
          "/run:/run"
        ]

        command = "kube-proxy"
        args = [
          "--kubeconfig=/etc/kubernetes/kubeconfig.conf",
          "--cluster-cidr=${CLUSTER_CIDR}"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 128 # 256MB
        network {
          mbits = 100
        }
      }
    }
  }
}