job "minio" {

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
      attempts = 10
      interval = "5m"
      delay = "25s"
      mode = "delay"
    }

    ephemeral_disk {
      migrate = true
      size = 300
    }

    task "server" {
      driver = "docker"

      env {
         MINIO_ACCESS_KEY = "${MINIO_ACCESS_KEY}"
         MINIO_SECRET_KEY = "${MINIO_SECRET_KEY}"
      }
      
      config {
        image = "minio/minio:RELEASE.2017-08-05T00-00-53Z"
        port_map {
          http = 9000
        }

        volumes = [
          "${NOMAD_ALLOC_DIR}/data:/data"
        ]

        args = [
          "server",
          "/data"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
        network {
          mbits = 10
          port "http" {}
        }
      }

      service {
        name = "minio"
        tags = ["global", "minio"]
        port = "http"
        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}