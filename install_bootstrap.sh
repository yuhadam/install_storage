#!/bin/bash
sshPort=$1
interface=$2
masterIpArr=$3
IFS=';' read -a masterIpArr <<< "$masterIpArr"
masterPwArr=$4
IFS=';' read -a masterPwArr <<< "$masterPwArr"
workerIpArr=$5
IFS=';' read -a workerIpArr <<< "$workerIpArr"
workerPwArr=$6
IFS=';' read -a workerPwArr <<< "$workerPwArr"
storageIpArr=$7
IFS=';' read -a storageIpArr <<< "$storageIpArr"
storagePwArr=$8
IFS=';' read -a storagePwArr <<< "$storagePwArr"
masterLen=${#masterIpArr[@]}
workerLen=${#workerIpArr[@]}
storageLen=${#storageIpArr[@]}
yum -y update
yum install -y net-tools
yum install -y wget

echo -e "\n" | ssh-keygen -t rsa -N ""

rpm -Uvh /install/sshpass-1.05-1.el7.rf.x86_64.rpm

for ((i=1;i<$masterLen;i++))
do
sshpass -p "${masterPwArr[$i]//\"/}" ssh-copy-id -o StrictHostKeyChecking=no root@${masterIpArr[$i]//\"/}
ssh root@${masterIpArr[$i]//\"/} "yum -y update && yum install -y git && cd /root/ && git clone http://www.github.com/yuhadam/install_storage2 && cd install_storage2 && ./install_nobootstrap.sh"
echo "####finish####"
done

for ((i=1;i<$workerLen;i++))
do
sshpass -p "${workerPwArr[$i]//\"/}" ssh-copy-id -o StrictHostKeyChecking=no root@${workerIpArr[$i]//\"/}
ssh root@${workerIpArr[$i]//\"/} "yum -y update && yum install -y git && cd /root/ && git clone http://www.github.com/yuhadam/install_storage2 && cd install_storage2 && ./install_nobootstrap.sh"
echo "####finish####"
done

for ((i=1;i<$storageLen;i++))
do
sshpass -p "${storagePwArr[$i]//\"/}" ssh-copy-id -o StrictHostKeyChecking=no root@${storageIpArr[$i]//\"/}
yum -y update
yum install -y tar xz unzip curl ipset nfs-utils
done

cat > /etc/yum.repos.d/docker.repo << '__EOF__'

[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
__EOF__

#cat > /etc/modules-load.d/overlay.conf << '__EOF__'
#overlay
#__EOF__

mkdir -p /etc/systemd/system/docker.service.d

cat > /etc/systemd/system/docker.service.d/override.conf << '__EOF__'
[Service]
ExecStart=
ExecStart=/usr/bin/docker daemon --storage-driver=overlay -H fd://
__EOF__


yum install -y docker-engine-1.11.2
yum install -y yum-versionlock
yum versionlock docker-engine

yum clean all

systemctl daemon-reload
systemctl start docker
systemctl enable docker
yum -y update

yum install -y tar xz unzip curl ipset nfs-utils
yum clean all

groupadd nogroup
yum -y update




yum install -y ntp


sed -i '21,24d' /etc/ntp.conf

sed -i '21s/$/server 0.kr.pool.ntp.org\n/' /etc/ntp.conf
sed -i '22s/$/server 1.asia.pool.ntp.org\n/' /etc/ntp.conf
sed -i '23s/$/server 3.asia.pool.ntp.org\n/' /etc/ntp.conf

systemctl start ntpd
systemctl enable ntpd


mkdir /dcos
chmod 777 /dcos
mkdir -p /dcos/genconf
cd /dcos
#cp -r ~/dcos_generate_config.sh /dcos
curl -O https://downloads.dcos.io/dcos/EarlyAccess/commit/14509fe1e7899f439527fb39867194c7a425c771/dcos_generate_config.sh
#cp /opt/dcos_generate_config.sh /dcos
cd genconf

echo "---" >> config.yaml
echo "agent_list:" >> config.yaml

for ((i=1;i<$workerLen;i++))
do
echo "- ${workerIpArr[$i]//\"/}" >> config.yaml
done

cat >> config.yaml << "EOF"
bootstrap_url: 'file:///opt/dcos_install_tmp'
cluster_name: dcos
exhibitor_storage_backend: static
master_discovery: static
master_list:
EOF


for ((i=1;i<$masterLen;i++))
do
echo "- ${masterIpArr[$i]//\"/}" >> config.yaml
done


cat >> config.yaml << "EOF"
resolvers:
- 8.8.4.4
- 8.8.8.8
ssh_key_path: /genconf/ssh_key
EOF

echo "ssh_port: $sshPort" >> config.yaml
echo "ssh_user: root" >> config.yaml
echo "oauth_enabled: 'false'" >> config.yaml


echo "#!/bin/bash" >> ip-detect
echo "set -o nounset -o errexit" >> ip-detect
echo "export PATH=/usr/sbin:/usr/bin:\$PATH" >> ip-detect
echo "echo \$(ip addr show $interface | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)" >> ip-detect


chmod 777 ip-detect config.yaml
cp /root/.ssh/id_rsa /dcos/genconf/ssh_key && chmod 0600 /dcos/genconf/ssh_key

cd /dcos/
bash dcos_generate_config.sh --genconf
bash dcos_generate_config.sh --install-prereqs
bash dcos_generate_config.sh --preflight
bash dcos_generate_config.sh --deploy
bash dcos_generate_config.sh --postflight && wait


ssh -T root@${storageIpArr[1]//\"/}<< EOSSH
yum install -y nfs-utils
mkdir -p /nfsdir
mkdir -p /nfsdir/bundle
mkdir -p /nfsdir/exe
chmod 777 /nfsdir
echo "/nfsdir *(rw,insecure,fsid=0,no_subtree_check,no_root_squash)" >> /etc/exports
systemctl restart nfs-server
systemctl restart nfs
systemctl enable nfs-server
EOSSH

ssh -T root@${masterIpArr[1]//\"/} << EOSSH
sed -i "s/daemon/daemon --insecure-registry ${masterIpArr[1]//\"/}:5000 /g" /etc/systemd/system/docker.service.d/override.conf
systemctl daemon-reload
systemctl restart docker
sleep 10s
docker run --restart=always -d -p 5000:5000 -e standalone=True -e disable_token_auth=True -v /opt/registry/:/var/lib/registry/ --name registry registry:2

cd /root/
git clone http://www.github.com/ichthysngs/installserver
cd installserver
yum install -y sqlite sqlite-devel
sqlite3 ichthys.db "insert into user values(0,'admin','${masterIpArr[1]//\"/}','');"
docker build --tag ichthysngs .
mkdir -p /nfsdir
chmod 777 /nfsdir
mount -t nfs ${storageIpArr[1]//\"/}:/nfsdir /nfsdir
./start.sh
EOSSH


for(( i=1; i<$workerLen; i++))
do
ssh -T root@${workerIpArr[$i]//\"/} << EOSSH
sed -i "s/daemon/daemon --insecure-registry ${masterIpArr[1]//\"/}:5000 /g" /etc/systemd/system/docker.service.d/override.conf
systemctl daemon-reload 
systemctl restart docker
mkdir -p /nfsdir
chmod 777 /nfsdir
mount -t nfs ${storageIpArr[1]//\"/}:/nfsdir /nfsdir
exit
EOSSH
done
sleep 10s

cd /install/

sed -i "7s/$/--http_notification_url http:\/\/${masterIpArr[1]//\"/}:9001\/fail\",/g" /install/chronos.json && wait
curl -L -H 'Content-Type: application/json' -X POST -d @chronos.json http://${masterIpArr[1]//\"/}:8080/v2/apps && wait
sleep 10s

echo "##############################################################################"
echo "###############            all finished              #########################"
echo "##############################################################################"




