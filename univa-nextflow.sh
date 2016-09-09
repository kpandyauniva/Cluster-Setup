#!/bin/bash

curl https://storage.googleapis.com/com-univa-nextflow/univa-nextflow.tar -o /tmp/univa-nextflow.tar

tar xf /tmp/univa-nextflow.tar -C /tmp

cd /tmp/Cluster-Setup

bash ./init-cluster.sh 1>/tmp/univa-nextflow-status.txt 2>/tmp/univa-nextflow-err.txt
