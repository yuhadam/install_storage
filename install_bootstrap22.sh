#!/bin/bash

index=0

for var in "$@"
do
array[$index]="$var"
((index+=1))
done

num=2
portNum=${array[$num]}

masterIpNum=1
masterip="${array[3]}"
arrlen=${#array[@]}



cd /dcos

mkdir dcosclidir && cd dcosclidir
curl -O https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-1.8/dcos
chmod +x dcos
./dcos config set core.dcos_url http://${array[3]}
./dcos auth login
echo "yes" | ./dcos package install chronos

sleep 30s

TEMP=$(./dcos marathon task list --json | grep -n "port" | grep -Eo '[0-9]{1,2}')

PORT_LINE=$(($TEMP+1))
ENDPOINT_PORT=$(./dcos marathon task list --json | sed "$PORT_LINE,$PORT_LINE!d" | sed 's/ //g')
ENDPOINT_IP=$(./dcos service | grep chronos | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)


ssh -T root@$masterip << EOSSH
git clone http://www.github.com/ichthysngs/installserver
cd installserver
sed -i "15s/^/curl -L -H 'Content-Type: application\/json' -X POST -d @docker.json $ENDPOINT_IP:$ENDPOINT_PORT/" launch.sh
sed -i "16s/^/curl -L -X PUT $ENDPOINT_IP:$ENDPOINT_PORT/" launch.sh
yum install -y sqlite sqlite-devel
sqlite3 ichthys.db "insert into user values(0,'admin','$masterip','');"
modprobe nfs
modprobe nfsd
service rpcbind stop
docker build --tag ichthysngs .
./start.sh
cd /root
rm -rf installserver
EOSSH

for(( i=3+$masterIpNum; i<$index; i++))
do
ssh -T root@${array[$i]} << EOSSH
mkdir -p /nfsdir
chmod 777 /nfsdir
mount -t nfs $masterip:/nfsdir /nfsdir
exit
EOSSH
done

