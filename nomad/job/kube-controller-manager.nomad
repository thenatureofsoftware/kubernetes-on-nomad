job "kube-controller-manager" {
  region = "global"
  datacenters = ["dc1"]
  type = "service"

  group "kube-controller-manager" {
    count = 1
    
    constraint {
      attribute = "${node.class}"
      operator  = "set_contains"
      value   = "kubelet"
    }

    task "kube-controller-manager" {
      driver = "raw_exec"

      template {
        destination = "local/kubernetes/controller-manager.conf"
        data      = <<EOF
{{key "kubernetes/controller-manager/kubeconfig" }}
EOF
      }
      template {
        destination = "local/kon/pki/ca.crt"
        data      = <<EOF
{{key "kon/pki/ca/cert"}}
EOF
      }
      template {
        destination = "local/kon/pki/ca.key"
        data      = <<EOF
{{key "kon/pki/ca/key"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/sa.key"
        data      = <<EOF
{{key "kubernetes/certs/sa/key"}}
EOF
      }
      template {
        destination = "local/kube-proxy.env"
        env         = true
        data      = <<EOH
CLUSTER_CIDR={{key "kubernetes/network/pod-network-cidr"}}
EOH
      }

      config {
        command = "/opt/bin/kube-controller-manager"
        args = [
          "--kubeconfig=local/kubernetes/controller-manager.conf",
          "--root-ca-file=local/kon/pki/ca.crt",
          "--controllers=*,bootstrapsigner,tokencleaner",
          "--service-account-private-key-file=local/kubernetes/pki/sa.key",
          "--cluster-signing-cert-file=local/kon/pki/ca.crt",
          "--cluster-signing-key-file=local/kon/pki/ca.key",
          "--address=${NOMAD_IP_controllerMgr}",
          "--leader-elect=true",
          "--use-service-account-credentials=true",
          "--allocate-node-cidrs=true",
          "--cluster-cidr=${CLUSTER_CIDR}",
          "--node-cidr-mask-size=24"
        ]
      }

      resources {
        network {    
          port "controllerMgr" {
            static = "10252"
          }
        }
      }

      service {
        name = "controller-manager"
        tags = ["global", "kubernetes", "kube-controller-manager"]
        port = "controllerMgr"

        check {
          type = "http"
          name = "check_kube-controller-manager"
          interval = "15s"
          timeout  = "15s"
          path = "/healthz"
          port = "controllerMgr"
          
          check_restart {
            limit = 5
            grace_period = "30s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}