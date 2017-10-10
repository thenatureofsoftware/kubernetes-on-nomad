job "kube-scheduler" {
  region = "global"
  datacenters = ["dc1"]
  type = "service"

  group "kube-scheduler-grp" {
    count = 1
    
    constraint {
      attribute = "${node.class}"
      operator  = "set_contains"
      value   = "kubelet"
    }

    task "kube-scheduler" {
      driver = "raw_exec"

      template {
        destination = "local/kubernetes/scheduler.conf"
        data      = <<EOF
{{key "kubernetes/scheduler/kubeconfig" }}
EOF
      }

      config {
        command = "/opt/bin/kube-scheduler"
        args    = [
          "--address=${NOMAD_IP_scheduler}",
          "--leader-elect=true",
          "--kubeconfig=local/kubernetes/scheduler.conf"
        ]
      }

      resources {
        network {    
          port "scheduler" {
            static = "10251"
          }
        }
      }

      service {
        name = "scheduler"
        tags = ["global", "kubernetes", "kube-scheduler"]
        port = "scheduler"

        check {
          type = "http"
          name = "check_kube-scheduler"
          interval = "15s"
          timeout  = "15s"
          path = "/healthz"
          port = "scheduler"
          
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