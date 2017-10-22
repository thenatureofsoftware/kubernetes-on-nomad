job "kube-apiserver" {
  region = "global"
  datacenters = ["dc1"]
  type = "service"

  group "kube-apiserver-grp" {
    count = 1
    
    constraint {
      attribute = "${node.class}"
      operator  = "set_contains"
      value   = "kubelet"
    }

    task "kube-apiserver" {
      driver = "raw_exec"

      template {
        destination = "local/kube-apiserver.env"
        env         = true
        data      = <<EOH
ETCD_SERVERS={{key "etcd/servers"}}
EOH
      }
      template {
        destination = "local/kon/pki/ca.crt"
        data      = <<EOF
{{key "kon/pki/ca/cert"}}
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
        command = "/opt/bin/kube-apiserver"
        args    = [
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
          "--client-ca-file=local/kon/pki/ca.crt",
          "--authorization-mode=Node,RBAC",
          "--advertise-address=${attr.unique.network.ip-address}",
          "--etcd-cafile=local/kon/pki/ca.crt",
          "--etcd-certfile=local/kubernetes/pki/apiserver-kubelet-client.crt",
          "--etcd-keyfile=local/kubernetes/pki/apiserver-kubelet-client.key",
          "--etcd-servers=https://etcd.service.consul:2379"
        ]
      }

      resources {
        network {    
          port "https" {
            static = "6443"
          }
        }
      }

      service {
        name = "kubernetes"
        tags = ["global", "kubernetes", "kube-apiserver"]
        port = "https"

        check {
          type = "script"
          name = "check_kube-apiserver"
          interval = "2s"
          timeout  = "5s"
          command = "/usr/bin/curl"
          args = [
            "--insecure",
            "--cacert", "${NOMAD_TASK_DIR}/kubernetes/pki/ca.crt",
            "--cert", "${NOMAD_TASK_DIR}/kubernetes/pki/apiserver-kubelet-client.crt",
            "--key", "${NOMAD_TASK_DIR}/kubernetes/pki/apiserver-kubelet-client.key",
            "https://${NOMAD_ADDR_https}/healthz"
          ]
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