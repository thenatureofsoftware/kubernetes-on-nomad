job "etcd" {
  region = "global"
  datacenters = ["dc1"]
  type = "system"

  update {
    max_parallel = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert = false
    canary = 0
  }


  group "etcd-servers" {
    count = 1

    constraint {
      attribute = "${node.class}"
      operator  = "set_contains"
      value   = "etcd"
    }

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

    task "server" {
      driver = "docker"

      template {
        destination = "local/etcd.env"
        env         = true
        data      = <<EOH
ETCD_INITIAL_CLUSTER={{key "etcd/initial-cluster"}}
ETCD_INITIAL_CLUSTER_TOKEN={{key "etcd/initial-cluster-token"}}
EOH
      }
      #NODE_STATUS={{printf "kubernetes/nodes/%s" (env "attr.unique.hostname") | key}}
      config {
        image = "gcr.io/google_containers/etcd-amd64:3.0.17"
        network_mode = "host"

        volumes = [
          "/etc/ssl/certs:/etc/ssl/certs",
          "${NOMAD_TASK_DIR}/kubernetes:/etc/kubernetes",
          "${NOMAD_ALLOC_DIR}/data:/var/lib/etcd"
        ]

        command = "etcd"
        args = [
          "--name", "${attr.unique.hostname}",
          "--initial-advertise-peer-urls", "http://${attr.unique.network.ip-address}:2380",  
          "--listen-peer-urls", "http://${attr.unique.network.ip-address}:2380",
          "--listen-client-urls", "http://${attr.unique.network.ip-address}:2379,http://127.0.0.1:2379",
          "--advertise-client-urls", "http://${attr.unique.network.ip-address}:2379",
          "--initial-cluster-token", "${ETCD_INITIAL_CLUSTER_TOKEN}",
          "--initial-cluster", "${ETCD_INITIAL_CLUSTER}",
          "--initial-cluster-state", "new",
          "--data-dir", "/var/lib/etcd"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
        network {
          mbits = 100
          port "http" {
            static = "2379"
          }
        }
      }

      service {
        name = "etcd"
        tags = ["global", "etcd"]
        port = "http"
      }
    }
  }
}