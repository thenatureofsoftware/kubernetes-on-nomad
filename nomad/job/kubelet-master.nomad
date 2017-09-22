# There can only be a single job definition per file. This job is named
# "example" so it will create a job with the ID and Name "example".

# The "job" stanza is the top-most configuration option in the job
# specification. A job is a declarative specification of tasks that Nomad
# should run. Jobs have a globally unique name, one or many task groups, which
# are themselves collections of one or many tasks.
#
# For more information and examples on the "job" stanza, please see
# the online documentation at:
#
#     https://www.nomadproject.io/docs/job-specification/job.html
#
job "kubelet-master" {
  region = "global"
  datacenters = ["dc1"]
  type = "service"

  update {
    max_parallel = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert = false
    canary = 0
  }


  group "tasks" {
    count = 1

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 10
      interval = "5m"

      delay = "25s"

      mode = "delay"
    }

    ephemeral_disk {
      size = 300
    }

    task "kubelet" {
      driver = "raw_exec"

      config {
        command = "/usr/bin/kubelet"
        args    = ["--kubeconfig=local/kubernetes/kubelet.conf",
                  "--require-kubeconfig=true",
                  "--pod-manifest-path=local/kubernetes/manifests",
                  "--allow-privileged=true",
                  "--network-plugin=cni",
                  "--cni-conf-dir=/etc/cni/net.d",
                  "--cni-bin-dir=/opt/cni/bin",
                  "--cluster-dns=${NOMAD_IP_kubelet}",
                  "--cluster-domain=cluster.local",
                  "--authorization-mode=Webhook",
                  "--client-ca-file=local/kubernetes/pki/ca.crt",
                  "--cadvisor-port=0"]
      }

      artifact {
        source = "${BOOTSTRAP_K8S_CONFIG_BUNDLE}"
        destination = "local/kubernetes"
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
        network {
          mbits = 10
          port "kubelet" {
            static = "10250"
          }
          port "heapster" {
            static = "10255"
          }
        }
      }
    }
  }
}