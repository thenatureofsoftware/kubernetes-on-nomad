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


  group "components" {
    count = 1

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 10
      interval = "5m"

      delay = "25s"

      mode = "delay"
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
      template {
        destination = "local/kubernetes/pki/ca.crt"
        data      = <<EOF
{{key "kubernetes/certs/ca/cert"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/front-proxy-client.crt"
        data      = <<EOF
{{key "kubernetes/certs/front-proxy-client/cert"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/front-proxy-client.key"
        data      = <<EOF
{{key "kubernetes/certs/front-proxy-client/key"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/apiserver-kubelet-client.crt"
        data      = <<EOF
{{key "kubernetes/certs/apiserver-kubelet-client/cert"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/front-proxy-ca.crt"
        data      = <<EOF
{{key "kubernetes/certs/front-proxy-ca/cert"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/apiserver.key"
        data      = <<EOF
{{key "kubernetes/certs/apiserver/key"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/apiserver.crt"
        data      = <<EOF
{{key "kubernetes/certs/apiserver/cert"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/apiserver-kubelet-client.key"
        data      = <<EOF
{{key "kubernetes/certs/apiserver-kubelet-client/key"}}
EOF
      }
      template {
        destination = "local/kubernetes/pki/sa.pub"
        data      = <<EOF
{{key "kubernetes/certs/sa/cert"}}
EOF
      }
      
      config {
        image = "gcr.io/google_containers/kube-apiserver-amd64:v1.7.6"
        network_mode = "host"
        dns_servers = ["127.0.0.1"]

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
        memory = 400 # 256MB
        network {
          mbits = 100
          port "https" {
            static = "6443"
          }
        }
      }

      service {
        name = "kubernetes"
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
        destination = "local/kubernetes/scheduler.conf"
        data      = <<EOF
{{key "kubernetes/scheduler/kubeconfig" }}
EOF
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