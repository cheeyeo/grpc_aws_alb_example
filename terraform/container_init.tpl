#!/bin/bash

sudo yum update -y

cat << EOF > /etc/ecs/ecs.config
ECS_CLUSTER=${clustername}
ECS_ENABLE_TASK_IAM_ROLE=true
ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs"]
ECS_CONTAINER_INSTANCE_PROPAGATE_TAGS_FROM=ec2_instance
ECS_CHECKPOINT=true
ECS_DATADIR=/data
EOF

sed -i '/After=cloud-final.service/d' /usr/lib/systemd/system/ecs.service
sudo systemctl daemon-reload
exec 2>>/var/log/ecs-agent-reload.log
set -x
until curl -s http://localhost:51678/v1/metadata; do sleep 1; done
docker plugin install rexray/ebs REXRAY_PREEMPT=true EBS_REGION=${region } --grant-all-permissions
sudo systemctl restart docker
sudo systemctl restart ecs

sudo sysctl -w net.ipv4.conf.all.route_localnet=1
sudo iptables -t nat -A PREROUTING -p tcp -d 169.254.170.2 --dport 80 -j DNAT --to-destination 127.0.0.1:51679
sudo iptables -t nat -A OUTPUT -d 169.254.170.2 -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 51679

sudo iptables-save