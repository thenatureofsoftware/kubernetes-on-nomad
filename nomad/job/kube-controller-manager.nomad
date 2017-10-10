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
        destination = "local/kubernetes/pki/ca.crt"
        data      = <<EOF
{{key "kubernetes/certs/ca/cert"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/ca.key"
        data      = <<EOF
{{key "kubernetes/certs/ca/key"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/sa.key"
        data      = <<EOF
{{key "kubernetes/certs/sa/key"}}
EOF
      }

      config {
        command = "/opt/bin/kube-controller-manager"
        args = [
          "--kubeconfig=local/kubernetes/controller-manager.conf",
          "--root-ca-file=local/kubernetes/pki/ca.crt",
          "--controllers=*,bootstrapsigner,tokencleaner",
          "--service-account-private-key-file=local/kubernetes/pki/sa.key",
          "--cluster-signing-cert-file=local/kubernetes/pki/ca.crt",
          "--cluster-signing-key-file=local/kubernetes/pki/ca.key",
          "--address=${NOMAD_IP_controllerMgr}",
          "--leader-elect=true",
          "--use-service-account-credentials=true"
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