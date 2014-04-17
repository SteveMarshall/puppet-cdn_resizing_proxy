# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "chef/ubuntu-12.04"
  config.vm.network "forwarded_port", guest: 80, host: 8000

  config.vm.provision "shell", inline: "sudo apt-get install -y puppet-common"
  config.librarian_puppet.puppetfile_dir = '.'
  config.vm.provision "puppet" do |puppet|
    puppet.module_path = "modules"
    puppet.manifest_file = "init.pp"
  end
end
