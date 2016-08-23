#!/bin/bash

setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/sysconfig/selinux
cd /tmp/unicloud-6.2.0-b291
./install-unicloud.sh 2>/tmp/unicloud_install_err.txt
source /opt/unicloud/etc/unicloud.sh
unicloud-setup --i-accept-the-eula --defaults  2>/tmp/unicloud_setup_err.txt
cd /tmp
install-kit --i-accept-the-eula kit-gce*.tar.bz2  2>/tmp/install_kit_err.txt
enable-component -p management
puppet agent -t
source /opt/unicloud/etc/unicloud.sh
./kubernetes-bootstrap.sh --no-provisioning-network --variant=fedora 2>/tmp/k8s_bootstrap_err.txt
for name in master worker; do
	copy-hardware-profile --src $name --dst ${name}-gce
        update-hardware-profile --name ${name}-gce --resource-adapter gce --location remote
    	set-profile-mapping --software-profile $name --hardware-profile ${name}-gce
done
