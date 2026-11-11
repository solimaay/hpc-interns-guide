# -*- mode: ruby -*-
# HPC Intern Lab: 1 login node + 1 compute node, Rocky Linux 9, about 1 GB RAM and 1 CPU each.
#
#   vagrant up        builds the nodes (login first); the first run downloads the box
#
# The nodes are listed in nodes.txt. The setup itself is in core/provision-base.sh.
# This folder is shared into every VM as /vagrant, so the scripts run straight from it.
# Chapter 7 adds modules/03-slurm/provision.sh:  vagrant provision <node> --provision-with slurm

NODES = File.readlines(File.join(__dir__, 'nodes.txt')).reject { |l| l =~ /^\s*(#|$)/ }.map(&:split)

# Compute nodes mount NFS from the login node, so the login node must finish first.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

Vagrant.configure('2') do |config|
  config.vm.box = 'generic/rocky9'
  config.vm.boot_timeout = 600

  NODES.each do |name, ip|
    config.vm.define name, primary: name == 'login' do |node|
      node.vm.hostname = name
      node.vm.network 'private_network', ip: ip

      node.vm.provider 'virtualbox' do |vb|
        vb.name = "hpc-#{name}"
        vb.memory = 1280
        vb.cpus = 1
        vb.linked_clone = true
      end
      node.vm.provider 'libvirt' do |lv, override|   # for Linux hosts without VirtualBox
        lv.memory = 1280
        lv.cpus = 1
        override.vm.synced_folder '.', '/vagrant', type: 'rsync'
      end

      node.vm.provision 'base',  type: 'shell', inline: 'bash /vagrant/core/provision-base.sh'
      node.vm.provision 'slurm', type: 'shell', inline: 'bash /vagrant/modules/03-slurm/provision.sh', run: 'never'
    end
  end
end
