#!/bin/bash
#___INFO__MARK_BEGIN__
#############################################################################
#
#  This code is the Property, a Trade Secret and the Confidential Information
#  of Univa Corporation.
#
#  Copyright Univa Corporation. All Rights Reserved. Access is Restricted.
#
#  It is provided to you under the terms of the
#  Univa Term Software License Agreement.
#
#  If you have any questions, please contact our Support Department.
#
#  www.univa.com
#
###########################################################################
#___INFO__MARK_END__

STATUS_CMD="sudo -i /opt/unicloud/bin/get-node-status --list --software-profile"
DELETE_CMD="sudo -i /opt/unicloud/bin/delete-node"
master_node=$($STATUS_CMD master | head -1 | awk -F'.' '{print $1}')
for worker_node in $($STATUS_CMD worker | awk -F'.' '{print $1}');
do
       echo "Deleting worker node: " $worker_node
        $DELETE_CMD --node=$worker_node
done
echo "Deleting master node: " $master_node
$DELETE_CMD --node=$master_node
