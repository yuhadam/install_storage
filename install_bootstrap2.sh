#!/bin/bash

index=0
echo -n "input network interface: "
read interfaceVar
array[$index]=$interfaceVar
((index+=1))

echo -n "input each password:"
read password
array[$index]=$password
((index+=1))

echo -n "input ssh port:"
read portNum
array[$index]=$portNum
((index+=1))

masterIpNum=0

while true; do
echo -n "input master ip (press q to quit):"
read masterip


if [ "$masterip" == "q" ]; then
 break
else
 array[$index]=$masterip
 ((masterIpNum+=1))
 ((index+=1))
fi

done


while true; do
echo -n "input worker ip(press q to quit):"
read value

if [ "$value" == "q" ]; then
 break
else
 array[$index]=$value
 ((index+=1))
fi

done

arrlen=${#array[@]}


cd /dcos && mkdir dcosclidir && cd dcosclidir
curl -O https://downloads.dcos.io/binaries/cli/darwin/x86-64/dcos-1.8/dcos
chmod +x dcos
./dcos config set core.dcos_url http://${array[3]}
dcos auth login
echo "yes" | ./dcos package install chronos

sleep 1m

TEMP=$(./dcos marathon task list --json | grep -n "port" | grep -Eo '[0-9]{1,2}')

PORT_LINE=$(($TEMP+1))
ENDPOINT_PORT=$(./dcos marathon task list --json | sed "$PORT_LINE,$PORT_LINE!d" | sed 's/ //g')
ENDPOINT_IP=$(./dcos service | grep chronos | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)


ssh -T root@$masterip << EOSSH
git clone http://github.com/ichthysngs/ichthysngs
cd ichthysngs
sed -i "15s/^/curl -L -H 'Content-Type: application\/json' -X POST -d @docker.json $ENDPOINT_IP:$ENDPOINT_PORT/" launch.sh
sed -i "16s/^/curl -L -X PUT $ENDPOINT_IP:$ENDPOINT_PORT/" launch.sh
modprobe nfs
modprobe nfsd
service rpcbind stop
docker build --tag ichthysngs .
./start.sh
rm -rf ichthysngs
EOSSH

for(( i=3+$masterIpNum; i<$index; i++))
do
ssh root@${array[$i]} "mkdir -p /nfsdir && chmod 777 /nfsdir && yum install -y nfs-utils && mount -t nfs $masterip:/nfsdir /nfsdir && exit"
done

echo "##############################################################################"
echo "###############            all finished              #########################"
echo "##############################################################################"















