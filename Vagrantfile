# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|

  config.vm.box = "bento/ubuntu-16.10"
  
  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
    v.cpus = 2
  end

  $server_count = 3

  def serverIP(num)
    return "172.17.4.#{num+100}"
  end

  config.ssh.insert_key = false

  (1..$server_count).each do |i|
    config.vm.define vm_name = "node%d" % i do |node|
      ip = serverIP(i)

      node.vm.hostname = vm_name
      node.vm.network :private_network, ip: ip

    
      # fix for resolv.conf
      node.vm.provision :shell, :inline => "printf 'nameserver 127.0.0.53\n' | cat - /etc/resolv.conf > temp && mv temp /etc/resolv.conf", :privileged => true

      # setup environment file
      setup_file = Tempfile.new('setup.env', :binmode => true)
      setup_file.write("ADVERTISE_IP=#{ip}\n")
      if i == 1
        setup_file.write("SERVER=true\n")
      else
        setup_file.write("SERVER=false\n")
        setup_file.write("SERVER_IP=#{serverIP(1)}\n")
      end
      setup_file.write("ETCD_SERVERS=http://#{serverIP(2)}:2379,http://#{serverIP(3)}:2379\n")
      setup_file.write("ETCD_INITIAL_CLUSTER=node2=http://#{serverIP(2)}:2380,node3=http://#{serverIP(3)}:2380,node#{i}=http://127.0.0.1:2380\n")
      setup_file.write("ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-dc1\n")
      setup_file.close
      node.vm.provision :file, :source => setup_file, :destination => "/tmp/setup.env"
      node.vm.provision :shell, :inline => "mv /tmp/setup.env /vagrant/setup.env", :privileged => true

      # consul.service environment file
      consul_env_file = Tempfile.new('consul.env', :binmode => true)
      if i == 1 
        consul_env_file.write("CONSUL_FLAGS=-advertise #{ip} -bootstrap-expect #{$server_count}\n")
      else
        consul_env_file.write("CONSUL_FLAGS=-advertise #{ip} -retry-join '#{serverIP(1)}'\n")
      end
      consul_env_file.close
      node.vm.provision :file, :source => consul_env_file, :destination => "/tmp/consul.env"
      node.vm.provision :shell, :inline => "mkdir -p /etc/consul && mv /tmp/consul.env /etc/consul/consul.env", :privileged => true

      # nomad.service environment file
      nomad_env_file = Tempfile.new('nomad.env', :binmode => true)
      nomad_env_file.close
      node.vm.provision :file, :source => nomad_env_file, :destination => "/tmp/nomad.env"
      node.vm.provision :shell, :inline => "mkdir -p /etc/nomad && mv /tmp/nomad.env /etc/nomad/nomad.env", :privileged => true

      node.vm.provision "shell", inline: <<-SHELL
      sudo DEBIAN_FRONTEND=noninteractive /vagrant/setup.sh
      SHELL
    end
  end

end
