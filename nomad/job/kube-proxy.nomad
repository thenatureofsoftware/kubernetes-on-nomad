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
POD_CLUSTER_CIDR={{key "kubernetes/kube-proxy/cluster-cidr"}}
KUBE_APISERVER_ADDRESS={{key "kubernetes/kube-proxy/master"}}
EOH
      }

      template {
        destination = "local/kubernetes/kubeconfig.conf"
        data      = <<EOF
{{key "kubernetes/admin/kubeconfig" }}
EOF
      }

      config {
        image = "gcr.io/google_containers/kube-proxy-amd64:v1.7.6"
        network_mode = "host"
        privileged = true
        
        volumes = [
          "local/kubernetes:/etc/kubernetes",
          "/var/lib/kube-proxy:/var/lib/kube-proxy",
          "/run/xtables.lock:/run/xtables.lock"
        ]

        command = "kube-proxy"
        args = [
          "--kubeconfig=/etc/kubernetes/kubeconfig.conf",
          "--cluster-cidr=${POD_CLUSTER_CIDR}",
          "--master=${KUBE_APISERVER_ADDRESS}"
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