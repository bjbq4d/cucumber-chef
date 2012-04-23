LXC_ROOTFS = "/var/lib/lxc/controller/rootfs"
controllers = search(:node, 'name:cucumber-chef-controller')
status = %x(lxc-info -n controller 2>&1)

# create the network configuration for our 'controller' lxc container
cookbook_file "/etc/lxc/controller" do
  source "controller-lxc-config"
  not_if { controllers.length > 0 }
end

# create our 'controller' lxc container
execute "lxc-create -n controller -f /etc/lxc/controller -t lucid-chef" do
  not_if { controllers.length > 0 }
end

# install our shell script which handles installing ruby, rubygems and chef in our 'controller' lxc container
cookbook_file "#{LXC_ROOTFS}/tmp/install-chef.sh" do
  source "lxc-install-chef"
  mode "0755"
  not_if { controllers.length > 0 }
end

# execute our chef installation script in the 'controller' lxc container
execute "chroot #{LXC_ROOTFS} /bin/bash -c '/tmp/install-chef.sh'" do
  not_if { controllers.length > 0 }
end

# install our chef 'client.rb' into our 'controller' lxc container
template "#{LXC_ROOTFS}/etc/chef/client.rb" do
  source "controller-client.erb"
  variables(:orgname => node["cucumber-chef"]["orgname"],
            :nodename => node["cucumber-chef"]["nodename"])
  not_if { controllers.length > 0 }
end

# install our chef "bootstrap" json data
cookbook_file "#{LXC_ROOTFS}/etc/chef/first-boot.json" do
  source "controller-first-boot"
  not_if { controllers.length > 0 }
end

# execute our chef "bootstrap"
execute "chroot #{LXC_ROOTFS} /bin/bash -c '/usr/bin/chef-client -j /etc/chef/first-boot.json'" do
  not_if { controllers.length > 0 }
end

# fire up the 'controller' lxc container
execute "lxc-start -d -n controller" do
  not_if { status.include?("RUNNING") }
end
