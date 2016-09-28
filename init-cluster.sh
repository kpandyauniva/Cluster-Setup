#!/bin/bash

readonly master_swprofile=master
readonly master_hwprofile=master-gce
readonly worker_swprofile=worker
readonly worker_hwprofile=worker-gce
readonly sshcmd="ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
readonly gluster_volume_name="gv0"
readonly gluster_brick_dir="/mnt/brick1/${gluster_volume_name}"
readonly gluster_volume_name_mnt="localhost:/${gluster_volume_name}"
readonly gluster_mnt_dir_name="/mnt/gluster"

readonly METADATA_SERVER_URL="http://metadata.google.internal/computeMetadata/v1"
readonly HDR="Metadata-Flavor: Google"
readonly METADATA_SERVER_ATTRIB_CMD="curl -s -f $METADATA_SERVER_URL/instance/attributes"

INSTALL_DIR="/tmp/Cluster-Setup"
YAML_DIR=$INSTALL_DIR


NUM_WORKERS=$($METADATA_SERVER_ATTRIB_CMD/node-cnt -H "$HDR")
MACHINE_TYPE=$($METADATA_SERVER_ATTRIB_CMD/node-machine -H "$HDR")
CLUSTER_MACHINE_IMAGE=$($METADATA_SERVER_ATTRIB_CMD/node-image -H "$HDR")
GLUSTER_DISK_SIZE=$($METADATA_SERVER_ATTRIB_CMD/node-gfs-disk-size -H "$HDR")
NEXTFLOW_VERSION=$($METADATA_SERVER_ATTRIB_CMD/nxf-ver -H "$HDR")
NODE_DISK_SIZE=$($METADATA_SERVER_ATTRIB_CMD/node-disk-size -H "$HDR")

ZONE=$(curl -s $METADATA_SERVER_URL/instance/zone -H "$HDR" | awk -F'/' '{print $4}')
PROJECT=$(curl -s $METADATA_SERVER_URL/project/project-id -H "$HDR")


MASTER_NODE_INCLUDED=false


function adapter_config() {

sed "s|%%PROJECT%%|$PROJECT|g; s|%%CLUSTER_MACHINE_IMAGE%%|$CLUSTER_MACHINE_IMAGE|g; s|%%MACHINE_TYPE%%|$MACHINE_TYPE|g; s|%%ZONE%%|$ZONE|g;" > /opt/unicloud/config/adapter-defaults-gce.conf << EOF
[resource-adapter]
zone=%%ZONE%%

# Filename of P12 key file downloaded from Google Compute Engine console.  If
# the path is not fully-qualified, it is assumed to reside in
# $TORTUGA_ROOT/config

# key =

# or

# Filename of JSON authentication file from Google Compute Engine console.
# If the path is not fully-qualified, it is assumed to reside in
# $TORTUGA_ROOT/config

json_keyfile = ServiceAccount.json

# Email address taken from "Service Account" section under "Credentials" in
# OAuth section.  Use "Create new Client ID" to create a new service account,
# as necessary.
#
# Only necesary if using p12 key file for authentication

# service_account_email =

type=%%MACHINE_TYPE%%
network = default
project=%%PROJECT%%

vpn = false

startup_script_template = startup_script.py

# Cut-and-paste the URL from the console under 'Images'

image_url=https://www.googleapis.com/compute/v1/projects/%%PROJECT%%/global/images/%%CLUSTER_MACHINE_IMAGE%%

#image_url=
# Default user associated with the SSH public key of the 'root' user.  GCE
# images have root logins disabled, so it is necessary to set the default SSH
# user.

default_ssh_user = centos

#
# Sample 'alternate' hardware profile definition; settings from
# 'resource-adapter' are used, with the exception of the values defined below
# to override the defaults
#

# [HARDWAREPROFILENAME]
# type =
# network =
# project =
# zone =
EOF
}

function start_cluster(){
#	set -x
	local cnt=0
	local SLEEP_TIME=60
	local maxtries=10
	master_node=""

	echo "Starting cluster.."
	update_profile
	while [ -z "$master_node" ] && [ $cnt -lt $maxtries ]
	do
       	 	sleep $SLEEP_TIME
        	msg=$(add-nodes -n1 --software-profile  $master_swprofile --hardware-profile $master_hwprofile)
   		master_node=$(get-node-status --list --software-profile  $master_swprofile | head -1 | awk -F'.' '{print $1}')
		((cnt++))
	done

	if [ -z "$master_node" ]; then
        	echo "Error: Master not created after several try..exiting "  | tee /dev/stderr
		exit 1
	else
		echo "Master node  $master_node created"
		echo "Adding worker nodes.."
        	add-nodes -n$NUM_WORKERS --software-profile $worker_swprofile --hardware-profile $worker_hwprofile
		if [ $? -ne 0 ]; then
			echo "Error adding worker nodes..exiting"  | tee /dev/stderr 
			exit 1
		else
			echo "..added "
		fi
	fi
	k8s_master=$master_node
}

function validate_input(){

        if ! [[ $NUM_WORKERS =~ ^[0-9]+$ ]] || [ $NUM_WORKERS -le 0 ]; then
	        echo "Warning: Invalid node-cnt, defaulting to 2" 
		NUM_WORKERS=2
	fi
	k8snodecnt=$NUM_WORKERS

        if ! [[ $GLUSTER_DISK_SIZE =~ ^[0-9]+$ ]] || [ $GLUSTER_DISK_SIZE -le 0 ]; then
                echo "Warning - input: invalid node-gfs-disk-size defaulting to 20" 
		GLUSTER_DISK_SIZE=20
        fi

        if ! [[ $NODE_DISK_SIZE =~ ^[0-9]+$ ]] || [ $NODE_DISK_SIZE -le 40 ]; then
                echo "Warning - input: invalid node-disk-size defaulting to 40" 
		NODE_DISK_SIZE=40
        fi

        if [  -z "$MACHINE_TYPE" ]; then
	        echo "Warning - input: invalid node-machine defaulting to n1-standard-2" 
		MACHINE_TYPE="n1-standard-2"
        fi

        if [  -z "$CLUSTER_MACHINE_IMAGE" ]; then
                echo "Warning - input: invalid node-image, defaulting to fedora-cloud-atomic-23-20160524 " 
		CLUSTER_MACHINE_IMAGE="fedora-cloud-atomic-23-20160524"
        fi
	gcloud compute images list $CLUSTER_MACHINE_IMAGE >/dev/null
	if [ $? -ne 0 ]; then
		echo "Error: your installer instance does not seem to service account with permission..exiting" | tee /dev/stderr
		exit 1
	fi
	local found=$(gcloud compute images list $CLUSTER_MACHINE_IMAGE | grep $CLUSTER_MACHINE_IMAGE | wc -l)
	if [ $found -ne 1 ]; then
		echo "Error: input image $CLUSTER_MACHINE_IMAGE does not exist..exiting" | tee /dev/stderr
		exit 1
	fi
	found=$(gcloud compute machine-types list $MACHINE_TYPE --zones=$ZONE | grep $MACHINE_TYPE | wc -l)
        if [ $found -ne 1 ]; then
                echo "Error: node-machine $MACHINE_TYPE does not exist..exiting" | tee /dev/stderr
                exit 1
        fi

}

#update profile to attach additional disk of specified size (that will be used as gluster disk)
function update_profile(){
        $(update-software-profile --name $worker_swprofile --update-partition root --disk-size $NODE_DISK_SIZE''GB)
	$(update-software-profile --name $worker_swprofile --add-partition data  --device 2.1 --no-preserve --no-boot-loader --file-system xfs  --size $GLUSTER_DISK_SIZE''GB --disk-size $GLUSTER_DISK_SIZE''GB)
        if [ $? -ne 0 ]; then
               echo "Error: could not update master profile for attached disk..exiting" | tee /dev/stderr
               exit 1
        fi

}


#-----------------------prepare_nodes-----------------------------
#execute command and if failed, wait and try again
function execute_retry(){
        local waitcnt=$1
        local cnt=0
	local SLEEP_TIME=30
         while [ $cnt -lt $waitcnt ]
         do
              $EXEC_CMD
              if [ $? -eq 0 ]; then
                 break
              else
                   sleep $SLEEP_TIME
                   ((cnt++))
             fi
        done
        if [ $cnt -eq $waitcnt ]; then
                echo "Error: executing " $EXEC_CMD "..exiting" | tee /dev/stderr
                exit 1;
        fi
}

#check that k8s is up, we do this by getting nodes from kubectl and expect that it same as k8snodecnt
# We try this few times so that k8s in all nodes have time to come up
function check_k8s_status(){
    local upcnt=0
    local ntries=0
    local maxtries=10
    local SLEEP_TIME=30

    while [ $upcnt -lt $k8snodecnt ] && [ $ntries -lt $maxtries ]
    do
        upcnt=$($sshcmd fedora@${master_node} kubectl get nodes | wc -l )
        ((upcnt--))  #deduct one for the header line
        ((ntries++))
        sleep $SLEEP_TIME
    done
    if [ $ntries -eq $maxtries ]; then
          echo "Error: executing " $EXEC_CMD "...exiting" | tee /dev/stderr
          exit 1;
    fi

}

#Get list of all worker nodes, copy yamls, change privileged flag and restart kubelet
function prepare_worker(){
        for worker_node in $(get-node-status --list --software-profile $worker_swprofile | awk -F'.' '{print $1}'); do

                #just see if system is up, try with simple ssh
                EXEC_CMD="$sshcmd fedora@${worker_node} exit"
                execute_retry 5

                #directory to save state for gluster
                 EXEC_CMD="$sshcmd fedora@${worker_node} sudo mkdir -p -m uog+rwx /var/lib/glusterd"
                execute_retry 5

                change_privileged_attribute ${worker_node}
                EXEC_CMD="$sshcmd fedora@${worker_node} sudo systemctl restart kubelet"
                execute_retry 5
        done
}

#Get master node (expected only one) copy yamls, change privileged flag and restart kubapiserver
function prepare_master(){
                EXEC_CMD="scp -q $YAML_DIR/*.yaml fedora@${master_node}:~fedora"
                execute_retry 5
                change_privileged_attribute ${master_node}
                EXEC_CMD="$sshcmd fedora@${master_node} sudo systemctl restart kube-apiserver"
                execute_retry 5
}

function launch_yamls(){
        $sshcmd fedora@${master_node} kubectl create -f kube-system-namespace.yaml
        $sshcmd fedora@${master_node} kubectl create -f dns-addon.yaml
        $sshcmd fedora@${master_node} kubectl create -f gluster.yaml
}

function change_privileged_attribute(){
        node=$1
        EXEC_CMD="$sshcmd fedora@${node} sudo cp /etc/kubernetes/config /etc/kubernetes/config.org"
        execute_retry 1
        $sshcmd fedora@${node} sudo 'sed s/--allow_privileged=false/--allow_privileged=true/  < /etc/kubernetes/config.org > ~fedora/config'
        $sshcmd fedora@${node} sudo cp ~fedora/config /etc/kubernetes/config
}
#----------------------------------prepare_nodes ----------------------------------------


#----------------------------------init-glusterfs---------------------------------------
#Check that all nodes have gluster (pod) running
function check_gluster_running(){
        local cnt=0
        #each worker node running one gluster pod
        local maxtries=10
	local SLEEP_TIME=60

        running_cnt=$($sshcmd fedora@${k8s_master} kubectl get pods -l app=gluster-node | grep Running | wc -l)

        while [ $running_cnt -lt $k8snodecnt ] &&  [ $cnt -lt $maxtries ]
        do
                sleep $SLEEP_TIME
                running_cnt=$($sshcmd fedora@${k8s_master} kubectl get pods -l app=gluster-node | grep Running | wc -l)
                ((cnt++))
        done
        if [ $running_cnt -eq 0 ]; then
                echo "Error: Gluster not running ..exiting" | tee /dev/stderr
                exit 1
        fi
        if [ $running_cnt -ne $k8snodecnt ]; then
                echo "Error: Not all worker nodes running gluster ..exiting"  | tee /dev/stderr
                exit 1
        fi
}

function start_gluster(){
	check_gluster_running
	echo "Gluster running"

        local SLEEP_TIME=60

	# Get list of all worker nodes
	declare -A worker_nodes=()
	for worker_node in $(get-node-status --list --software-profile $worker_swprofile | awk -F'.' '{print $1}'); do
    		worker_nodes[$worker_node]=1
	done
	[[ -n ${worker_nodes[@]} ]] || {
    		echo "Error: no nodes in software profile [$worker_swprofile] .. exiting" | tee /dev/stderr
    		exit 1
	}


	# Find all pods labeled "app=gluster-node" (created by the DaemonSet)
	tmp_pod_tuples=($($sshcmd fedora@${k8s_master} kubectl get pods -l app=gluster-node --output=jsonpath=\"{range .items[\*]}{.metadata.name}/{.status.podIP}/{.spec.nodeName} {end}\"))
	pod_tuples=()
	worker_node_list=() 
	for tmp_pod_tuple in ${tmp_pod_tuples[@]}; do
    		pod_name=$(echo $tmp_pod_tuple | cut -f1 -d/)
    		pod_ip=$(echo $tmp_pod_tuple | cut -f2 -d/)
    		worker_node=$(echo $tmp_pod_tuple | cut -f3 -d/)
    		[[ -z ${worker_nodes[$worker_node]} ]] || {
       			 worker_node_list+=($worker_node)
       			 pod_tuples+=($tmp_pod_tuple)
    		}
	done
	[[ -n ${pod_tuples[@]} ]] || {
    		echo "No eligible pods with tag app=gluster-node ..exiting" | tee /dev/stderr
    		exit 1
	}

	# Iterate over all 'gluster-app' pods
	for pod_tuple in ${pod_tuples[@]}; do
    		pod_name=$(echo $pod_tuple | cut -f1 -d/)
    		pod_ip=$(echo $pod_tuple | cut -f2 -d/)
    		if [[ $pod_tuple == ${pod_tuples[0]} ]]; then
       			 readonly first_pod_name=$pod_name
       			 readonly first_pod_ip=$pod_ip
       			 readonly run_gluster_cmd="$sshcmd fedora@${k8s_master} kubectl exec -i $first_pod_name"
       			 first_pod=1
    		else
       			 first_pod=0
    		fi
    		nodespec+=" ${pod_ip}:$gluster_brick_dir"
    		[[ $first_pod -eq 1 ]] && {
       			 echo "Checking if Gluster volume ${gluster_volume_name} exists..."
       			 $run_gluster_cmd -- gluster volume info ${gluster_volume_name} 2>/dev/null
       			 volume_exists_result=$?
    		}
    		[[ $volume_exists_result -ne 0 ]] && {
       			 # Gluster volume does *NOT* already exist
        		echo "Probing Gluster peer $pod_ip"

        		$run_gluster_cmd -- gluster peer probe $pod_ip

        		[[ $? -eq 0 ]] || {
            			echo "Error: unable to probe for peer $pod_ip ..exiting"  | tee /dev/stderr
            			exit 1
        		}
    		}
    		# Ensure the brick directory exists on each peer
    		$sshcmd fedora@${k8s_master} kubectl exec -i $pod_name -- mkdir -p -m a+rwx $gluster_brick_dir
	done

	# Create the Gluster volume
	if [[ $volume_exists_result -ne 0 ]]; then
    		readonly cmd="gluster volume create ${gluster_volume_name} replica ${#pod_tuples[@]} $nodespec"
    		$run_gluster_cmd -- $cmd
    		[[ $? -eq 0 ]] || {
       			 echo "Error: Gluster 'volume create' failed ..exiting " | tee /dev/stderr
       			 exit 1
    		}
	fi
	# Start Gluster volume
	echo "Starting Gluster volume ${gluster_volume_name}.."
	$run_gluster_cmd -- gluster volume start $gluster_volume_name
	$run_gluster_cmd -- gluster volume set $gluster_volume_name nfs.disable off
	sleep $SLEEP_TIME   #give some time to have nfs.disable propogate
}
#----------------------------init-glusterfs.sh------------


#---------------------------mountnfs---------------------
#set -x
function execute_retry_mnt(){
        local waitcnt=$1
        local cnt=0
	local SLEEP_TIME=30

         while [ $cnt -lt $waitcnt ]
         do
              $EXEC_CMD
              if [ $? -eq 0 ]; then
                 break
              else
                   sleep $SLEEP_TIME
                   ((cnt++))
             fi
        done
        if [ $cnt -eq $waitcnt ]; then
                echo "Error: executing " $EXEC_CMD "..exiting" | tee /dev/stderr
                exit 1;
        fi
}
function mount_nfs(){
	readonly mountcmd="sudo mount $gluster_volume_name_mnt $gluster_mnt_dir_name"
	readonly addtofstab_cmd="echo $gluster_volume_name_mnt $gluster_mnt_dir_name nfs defaults 0 0 | sudo tee -a /etc/fstab"
	local sharing_worker_node=""

	# Get list of all worker nodes
	for worker_node in $(get-node-status --list --software-profile $worker_swprofile | awk -F'.' '{print $1}'); do
       	 	EXEC_CMD="$sshcmd fedora@${worker_node} sudo mkdir -p -m a+rwx $gluster_mnt_dir_name"
       	 	execute_retry_mnt 5
        	EXEC_CMD="$sshcmd fedora@${worker_node} $mountcmd"
        	execute_retry_mnt 5
		EXEC_CMD="$sshcmd fedora@${worker_node} $addtofstab_cmd"
        	execute_retry_mnt 5
		sharing_worker_node=${worker_node}
	done
	echo "sharing node: $sharing_worker_node"
	if [ "$MASTER_NODE_INCLUDED" = true ]; then
        	EXEC_CMD="$sshcmd fedora@${master_node} sudo mkdir -p -m a+rwx $gluster_mnt_dir_name"
        	execute_retry_mnt 5
        	EXEC_CMD="$sshcmd fedora@${master_node} sudo mount $sharing_worker_node:/$gluster_volume_name $gluster_mnt_dir_name"
        	execute_retry_mnt 5
		EXEC_cmd="$sshcmd fedora@${master_node} $addtofstab_cmd"
        	execute_retry_mnt 5
	fi
	mkdir -p -m a+rwx $gluster_mnt_dir_name; mount $sharing_worker_node:/$gluster_volume_name $gluster_mnt_dir_name
        echo $sharing_worker_node:/$gluster_volume_name $gluster_mnt_dir_name nfs defaults 0 0 | sudo tee -a /etc/fstab
}
#-------------------------mount-nfs  - end

#-------------------------prepare nextflow env begin
function prepareNextflow(){
   mkdir -p -m a+rwx /opt/nextflow
   cd /opt/nextflow
   curl -fsSL get.nextflow.io | bash

sed "s|%%NEXTFLOW_VERSION%%|$NEXTFLOW_VERSION|g" > /opt/nextflow/univa-nextflow-env.sh << EOF 
export NXF_VER=%%NEXTFLOW_VERSION%%
export PATH=/opt/nextflow:$PATH
export NXF_WORK=$gluster_mnt_dir_name/work
export NXF_ASSETS=$gluster_mnt_dir_name/projects
export NXF_EXECUTOR=k8s
export CAPSULE_CACHE_DIR=/.nextflow/capsule
EOF
 ln -s /opt/nextflow/univa-nextflow-env.sh /etc/profile.d/univa-nextflow-env.sh
 chmod a+rwx /opt/nextflow/*
 chmod a+rwx /.nextflow/capsule
}

#-------------------------prepare nextflow env end

#-------------------------prepare k8s on installer - begin
function prepareInstaller(){
	curl https://storage.googleapis.com/kubernetes-release/release/v1.2.4/bin/linux/amd64/kubectl -o  /usr/local/sbin/kubectl
	chmod +x /usr/local/sbin/kubectl 
	prepareNextflow
}
#-------------------------prepare k8s on installer - end

#-------------------------validate gcloud permissions
function validateGcloudPermissions(){
        gcloud components install beta -q
        echo "gcloud beta installed.."
        SERVICE_ACCOUNT=$(gcloud beta config list core/account 2>/dev/null | grep account | awk {'print $3'})
        if [ -z "$SERVICE_ACCOUNT" ]; then
              echo " Error:  Could not get service account, please ensure that your IAM apis are enabled and your account has sufficient permission..exiting " | tee /dev/stderr
              exit 1
        fi
}
#------------------------

#--------------------------create key json file
function createSvcAccountKey(){

	gcloud beta iam service-accounts keys create --iam-account $SERVICE_ACCOUNT --key-file-type=json /tmp/ServiceAccount.json
	if [ $? -ne 0 ]; then
		echo "Error: Could not create account key. Please ensure that IAM apis are enabled and key quota is available." | tee /dev/stderr
		exit 1
	fi
}

validateGcloudPermissions
validate_input
createSvcAccountKey

#TEMP work around until we have unicloud image for gce - begin
cd $INSTALL_DIR
bash ./setup-unicloud.sh

echo "Unicloud installed"
#TEMP work around until we have unicloud image for gce - end

cp /tmp/ServiceAccount.json /opt/unicloud/config
echo "ServiceAccount file added to Unicloud"

prepareInstaller

source /opt/unicloud/etc/unicloud.sh
cd $INSTALL_DIR

chmod a+x delete-k8s-cluster.sh 
cp delete-k8s-cluster.sh /opt/unicloud/bin

adapter_config
start_cluster

check_k8s_status
echo "Kubernetes running"
prepare_master
prepare_worker
echo "Kubernetes master and workers configured"
launch_yamls
echo "Pods launched"

start_gluster

echo "Mounting gluster volume to $gluster_mnt_dir_name .."
mount_nfs
echo "..mounted"

#setup link to master node for the installer (for kubectl)
ssh -f -nNT -L 8080:127.0.0.1:8080 fedora@${master_node}
echo "ssh -f -nNT -L 8080:127.0.0.1:8080 fedora@${master_node}" >/opt/unicloud/etc/univa-k8s-env.sh
echo "...done"
