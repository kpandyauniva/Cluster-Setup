#!/bin/bash

setenforce 0
sed -i 's/enforcing/permissive/' /etc/sysconfig/selinux
cd unicloud-6.2.0-b291
./install-unicloud.sh
source /opt/unicloud/etc/unicloud.sh
unicloud-setup --i-accept-the-eula --defaults
cd /tmp
install-kit --i-accept-the-eula kit-gce*.tar.bz2
enable-component -p management
puppet agent -t
source /opt/unicloud/etc/unicloud.sh
./kubernetes-bootstrap.sh --no-provisioning-network --variant=fedora
for name in master worker; do
	copy-hardware-profile --src $name --dst ${name}-gce
        update-hardware-profile --name ${name}-gce --resource-adapter gce --location remote
    	set-profile-mapping --software-profile $name --hardware-profile ${name}-gce
done
