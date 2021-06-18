#!/bin/bash

# Load config
. config.sh

# Ensure the user
adduser $sbs_subuser

# Update
apt-get update
apt-get upgrade -y

# Install packages
DEBIAN_FRONTEND=noninteractive apt-get install -y git curl wget jq vim util-linux sudo \
  vnstat iftop iotop htop powertop \
  psad unattended-upgrades ufw iptables-persistent \
  apt-transport-https ca-certificates gnupg lsb-release

# Install docker and docker-compose
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

sbs_var_compose_version=$(curl -sL "https://api.github.com/repos/docker/compose/releases/latest" | jq --raw-output '.tag_name' | grep -Eo '[0-9]+.[0-9]+.[0-9]+')
curl -L "https://github.com/docker/compose/releases/download/${sbs_var_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Register subuser to docker group
adduser "$sbs_subuser" docker

# Set iptables rules
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A INPUT -j LOG
iptables -A FORWARD -j LOG
ip6tables -A INPUT -j LOG
ip6tables -A FORWARD -j LOG
netfilter-persistent save

# Set some kernel params
sed -i 's/#net.ipv4.conf.default.rp_filter=1/net.ipv4.conf.default.rp_filter=1/' /etc/sysctl.conf
sed -i 's/#net.ipv4.conf.all.rp_filter=1/net.ipv4.conf.all.rp_filter=1/' /etc/sysctl.conf
sed -i 's/#net.ipv4.conf.all.accept_source_route = 0/net.ipv4.conf.all.accept_source_route = 0/' /etc/sysctl.conf
sed -i 's/#net.ipv6.conf.all.accept_source_route = 0/net.ipv6.conf.all.accept_source_route = 0/' /etc/sysctl.conf
sed -i 's/#net.ipv4.conf.all.send_redirects = 0/net.ipv4.conf.all.send_redirects = 0/' /etc/sysctl.conf
sed -i 's/#net.ipv4.tcp_syncookies=1/net.ipv4.tcp_syncookies=1/' /etc/sysctl.conf
sed -i 's/#net.ipv4.conf.all.log_martians = 1/net.ipv4.conf.all.log_martians = 1/' /etc/sysctl.conf
sed -i 's/#net.ipv4.conf.all.accept_redirects = 0/net.ipv4.conf.all.accept_redirects = 0/' /etc/sysctl.conf
sed -i 's/#net.ipv6.conf.all.accept_redirects = 0/net.ipv6.conf.all.accept_redirects = 0/' /etc/sysctl.conf
sysctl -p

# Setup psad
service rsyslog restart
cp -f ./setup/config/psad.conf /etc/psad/psad.conf
service psad restart
psad --sig-update
psad -H
psad -R
psad --fw-analyze

# Start services on boot
service docker start
service vnstat start
systemctl enable docker vnstat iptables psad

# Setup xanmod kernel
echo 'deb http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-kernel.list
wget -qO - https://dl.xanmod.org/gpg.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/xanmod-kernel.gpg add -
apt-get update
apt-get install linux-xanmod -y

# Setup acme.sh
sudo -u $sbs_subuser \
  curl https://get.acme.sh | sh -s email=$sbs_email && \
  ~/.acme.sh/acme.sh --issue --dns dns_cf -d doujinshiman.ga -d beta.doujinshiman.ga

echo "export CF_Key=\"$sbs_cf_key\"" >> $sbs_subuser_home/.acme.sh/account.conf
echo "export CF_Email=\"$sbs_email\"" >> $sbs_subuser_home/.acme.sh/account.conf

# Prepare docker containers
mkdir -p $sbs_subuser_home/containers

cp -r ./docker/database $sbs_subuser_home/containers
cp -r ./docker/gateway $sbs_subuser_home/containers

ln -s $sbs_subuser_home/.acme.sh $sbs_subuser_home/containers/certs

git clone https://github.com/Saebasol/Heliotrope.git $sbs_subuser_home/containers/Heliotrope
cp -f ./docker/Heliotrope/docker-compose.yml $sbs_subuser_home/containers/Heliotrope/docker-compose.yml

# Re-apply perms
chown -R $sbs_subuser:$sbs_subuser $sbs_subuser_home

# Start services
sudo -u $sbs_subuser bash -c : && _runas="sudo -u $sbs_subuser"
$_runas bash<<EOF
  docker network create -d bridge saebasol

  cd ~/containers/database
  docker-compose up -d
  cd ~/containers/gateway
  docker-compose up -d
  cd ~/containers/Heliotrope
  docker-compose up -d

  docker ps
EOF

# Remove stuffs
apt autoremove -y
cd
rm -r ~/install
