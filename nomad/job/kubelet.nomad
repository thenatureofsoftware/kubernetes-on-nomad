job "kubelet" {
  region = "global"
  datacenters = ["dc1"]
  type = "system"

  group "kubelet-grp" {
    count = 1

    constraint {
      attribute = "${node.class}"
      operator  = "set_contains"
      value   = "kubelet"
    }

    task "kubelet" {
      driver = "raw_exec"

      template {
        destination = "local/kubernetes/kubelet.conf"
        data      = <<EOF
{{printf "kubernetes/minions/%s/kubeconfig" (env "attr.unique.hostname") | key }}
EOF
      }

      template {
        destination = "local/kon/pki/ca.crt"
        data      = <<EOF
{{key "kon/pki/ca/cert"}}
EOF
      }

      config {
        command = "/opt/bin/kubelet"
        args    = ["--node-ip=${attr.unique.network.ip-address}",
                  "--fail-swap-on=false",
                  "--kubeconfig=local/kubernetes/kubelet.conf",
                  "--require-kubeconfig=true",
                  "--pod-manifest-path=/etc/kubernetes/manifests",
                  "--allow-privileged=true",
                  "--network-plugin=cni",
                  "--cni-conf-dir=/etc/cni/net.d",
                  "--cni-bin-dir=/opt/cni/bin",
                  "--cluster-dns=10.96.0.10",
                  "--cluster-domain=cluster.local",
                  "--authorization-mode=Webhook",
                  "--client-ca-file=local/kon/pki/ca.crt",
                  "--cadvisor-port=4194"]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
        network {
          mbits = 100
          port "kubelet" {
            static = "10250"
          }
          port "heapster" {
            static = "10255"
          }
          port "cadvisor" {
            static = "4194"
          }
        }
      }

      service {
        name = "kubelet-${attr.unique.hostname}"
        tags = ["global", "kubelet"]
        port = "kubelet"
        check {
          type = "http"
          port = "cadvisor"
          path = "/healthz"
          interval = "5s"
          timeout = "15s"
        }
      }
    }
  }
}