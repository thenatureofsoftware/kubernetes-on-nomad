job "etcd" {
  region = "global"
  datacenters = ["dc1"]
  type = "system"
  priority = 100

  group "etcd-grp" {

    constraint {
      attribute = "${node.class}"
      operator  = "set_contains"
      value   = "etcd"
    }

    task "etcd" {
      driver = "docker"

      template {
        destination = "local/etcd.env"
        env         = true
        data      = <<EOH
ETCD_INITIAL_CLUSTER={{key "etcd/initial-cluster"}}
ETCD_INITIAL_CLUSTER_TOKEN={{key "etcd/initial-cluster-token"}}
EOH
      }
      template {
        destination = "local/kon/pki/ca.crt"
        data      = <<EOF
{{key "kon/pki/ca/cert"}}
EOF
      }
      template {
        destination = "local/kon/pki/etcd.service.consul.crt"
        data      = <<EOF
{{key "etcd/service/cert"}}
EOF
      }
      template {
        destination = "local/kon/pki/etcd.service.consul.key"
        data      = <<EOF
{{key "etcd/service/key"}}
EOF
      }
      #NODE_STATUS={{printf "kubernetes/nodes/%s" (env "attr.unique.hostname") | key}}
      config {
        image = "gcr.io/google_containers/etcd-amd64:3.0.17"
        network_mode = "host"

        volumes = [
          "local/kon/pki:/etc/kon/pki",
          "local/data:/var/lib/etcd"
        ]

        command = "etcd"
        args = [
          "--debug=true",
          "--name", "${attr.unique.hostname}",
          "--initial-advertise-peer-urls=https://${NOMAD_ADDR_peer}",
          "--listen-peer-urls=https://${NOMAD_ADDR_peer}",
          "--listen-client-urls=https://${NOMAD_ADDR_https},https://127.0.0.1:2379",
          "--advertise-client-urls=https://etcd.service.consul:2379",
        #  "--initial-cluster-token=${ETCD_INITIAL_CLUSTER_TOKEN}",
        #  "--initial-cluster=${ETCD_INITIAL_CLUSTER}",
          "--initial-cluster-state=new",
          "--data-dir=/var/lib/etcd",
          "--trusted-ca-file=/etc/kon/pki/ca.crt",
          "--cert-file=/etc/kon/pki/etcd.service.consul.crt",
          "--key-file=/etc/kon/pki/etcd.service.consul.key",
        #  "--client-cert-auth=true",
        #  "--auto-tls",
          "--peer-auto-tls"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 384 # 256MB
        network {
          port "https" {
            mbits = 100
            static = "2379"
          }
          port "peer" {
            mbits = 100
            static = "2380"
          }
        }
      }

      service {
        name = "etcd"
        tags = ["etcd"]
        port = "https"
        check {
          type = "http"
          name = "check_etcd"
          interval = "5s"
          timeout  = "5s"
          path = "/health"
          tls_skip_verify = true
          protocol = "https"
          check_restart {
            limit = 5
            grace = "30s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}