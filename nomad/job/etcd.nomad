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
          "/etc/ssl/certs:/etc/ssl/certs",
          "local/data:/var/lib/etcd"
        ]

        command = "etcd"
        args = [
          "--name", "${attr.unique.hostname}",
          "--initial-advertise-peer-urls=https://${attr.unique.network.ip-address}:2380",  
          "--listen-peer-urls=https://${attr.unique.network.ip-address}:2380",
          "--listen-client-urls=https://${attr.unique.network.ip-address}:2379,https://127.0.0.1:2379",
          "--advertise-client-urls=https://etcd.service.consul:2379",
        #  "--initial-cluster-token=${ETCD_INITIAL_CLUSTER_TOKEN}",
        #  "--initial-cluster=${ETCD_INITIAL_CLUSTER}",
          "--initial-cluster-state=new",
          "--data-dir=/var/lib/etcd",
          "--trusted-ca-file=local/kon/pki/ca.crt",
          "--cert-file=local/kon/pki/etcd.service.consul.crt",
          "--key-file=local/kon/pki/etcd.service.consul.key",
          "--client-cert-auth=true",
          "--peer-auto-tls"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
        network {
          mbits = 100
          port "https" {
            static = "2379"
          }
        }
      }

      service {
        name = "etcd"
        tags = ["global", "etcd"]
        port = "https"
        check {
          type = "script"
          command = "/usr/bin/curl"
          args = [
            "--insecure",
            "--cacert local/kon/pki/ca.crt",
            "--cert local/kon/pki/etcd.service.consul.crt",
            "--key local/kon/pki/etcd.service.consul.key",
            "https://${attr.unique.network.ip-address}:2379/health"
          ]
          interval = "5s"
          timeout = "15s"
        }
      }
    }
  }
}