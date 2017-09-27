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
job "kube-control-plane" {
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


  group "grp" {
    count = 1

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 10
      interval = "5m"

      delay = "25s"

      mode = "delay"
    }

    ephemeral_disk {
      migrate = true
      size = 500
    }

    task "kube-apiserver" {
      driver = "docker"

      template {
        destination = "local/kube-apiserver.env"
        env         = true
        data      = <<EOH
ETCD_SERVERS={{key "etcd/servers"}}
EOH
      }

      artifact {
        source = "$BOOTSTRAP_K8S_CONFIG_BUNDLE"
        destination = "local/kubernetes"
      }
      
      config {
        image = "gcr.io/google_containers/kube-apiserver-amd64:v1.7.6"
        network_mode = "host"

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs",
          "${NOMAD_TASK_DIR}/kubernetes:/etc/kubernetes"
        ]

        command = "kube-apiserver"
        args = [
                "--proxy-client-cert-file=local/kubernetes/pki/front-proxy-client.crt",
                "--proxy-client-key-file=local/kubernetes/pki/front-proxy-client.key",
                "--insecure-port=0",
                "--requestheader-extra-headers-prefix=X-Remote-Extra-",
                "--kubelet-client-certificate=local/kubernetes/pki/apiserver-kubelet-client.crt",
                "--requestheader-client-ca-file=local/kubernetes/pki/front-proxy-ca.crt",
                "--tls-cert-file=local/kubernetes/pki/apiserver.crt",
                "--tls-private-key-file=local/kubernetes/pki/apiserver.key",
                "--admission-control=Initializers,NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeLabel,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota",
                "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
                "--requestheader-username-headers=X-Remote-User",
                "--requestheader-group-headers=X-Remote-Group",
                "--requestheader-allowed-names=front-proxy-client",
                "--kubelet-client-key=local/kubernetes/pki/apiserver-kubelet-client.key",
                "--secure-port=6443",
                "--allow-privileged=true",
                "--experimental-bootstrap-token-auth=true",
                "--service-cluster-ip-range=10.96.0.0/12",
                "--service-account-key-file=local/kubernetes/pki/sa.pub",
                "--client-ca-file=local/kubernetes/pki/ca.crt",
                "--authorization-mode=Node,RBAC",
                "--advertise-address=${attr.unique.network.ip-address}",
                "--etcd-servers=${ETCD_SERVERS}"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 1024 # 256MB
        network {
          mbits = 100
          port "https" {
            static = "6443"
          }
        }
      }

      service {
        name = "kube-apiserver"
        tags = ["global", "kubernetes", "apiserver"]
        port = "https"
      }
    }

    task "kube-controller-manager" {
      driver = "docker"

      template {
        destination = "local/kube-apiserver.env"
        env         = true
        data      = <<EOH
ETCD_SERVERS={{key "etcd/servers"}}
EOH
      }

      artifact {
        source = "$BOOTSTRAP_K8S_CONFIG_BUNDLE"
        destination = "local/kubernetes"
      }
      
      config {
        image = "gcr.io/google_containers/kube-controller-manager-amd64:v1.7.6"
        network_mode = "host"

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs",
          "${NOMAD_TASK_DIR}/kubernetes:/etc/kubernetes"
        ]

        command = "kube-controller-manager"
        args = [
          "--kubeconfig=local/kubernetes/controller-manager.conf",
          "--root-ca-file=local/kubernetes/pki/ca.crt",
          "--controllers=*,bootstrapsigner,tokencleaner",
          "--service-account-private-key-file=local/kubernetes/pki/sa.key",
          "--cluster-signing-cert-file=local/kubernetes/pki/ca.crt",
          "--cluster-signing-key-file=local/kubernetes/pki/ca.key",
          "--address=127.0.0.1",
          "--leader-elect=true",
          "--use-service-account-credentials=true"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
        network {
          mbits = 100
          port "controller" {
            static = "10252"
          }
        }
      }

      service {
        name = "kube-controller-manager"
        tags = ["global", "kubernetes", "controller-manager"]
        port = "controller"
        check {
          type     = "http"
          port     = "controller"
          path     = "/healthz"
          interval = "5s"
          timeout  = "2s"
        }
      }
    }

    task "kube-scheduler" {
      driver = "docker"

      template {
        destination = "local/kube-apiserver.env"
        env         = true
        data      = <<EOH
ETCD_SERVERS={{key "etcd/servers"}}
EOH
      }

      artifact {
        source = "$BOOTSTRAP_K8S_CONFIG_BUNDLE"
        destination = "local/kubernetes"
      }
      
      config {
        image = "gcr.io/google_containers/kube-scheduler-amd64:v1.7.6"
        network_mode = "host"

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs",
          "${NOMAD_TASK_DIR}/kubernetes:/etc/kubernetes"
        ]

        command = "kube-scheduler"
        args = [
          "--address=127.0.0.1",
          "--leader-elect=true",
          "--kubeconfig=local/kubernetes/scheduler.conf"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
        network {
          mbits = 100
          port "scheduler" {
            static = "10251"
          }
        }
      }

      service {
        name = "kube-scheduler"
        tags = ["global", "kubernetes", "scheduler"]
        port = "scheduler"
        check {
          type     = "http"
          port     = "10251"
          path     = "/healthz"
          interval = "5s"
          timeout  = "2s"
        }
      }
    }
  }
}