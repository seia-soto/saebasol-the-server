#!/bin/bash

set -e

if ! [ "${$(id -u) = 0}" ]; then
  echo "ERROR: To perform server setup, please run this script as root!"
  exit 1
fi
if ! [[ test -f "../is_root" ]]; then
  echo "ERROR: To perform server setup, please run this script at the top level of git repository!"
  exit 1
fi

function sbs_help() {
  cat <<-'EOF'
initial-setup.sh
Scripts to setup Heliotrope in one line.

Usage:
  sh ./setup/initial-setup.sh

  <subuser>     Subuser to run docker containers and services
  -h, --help    Display this mKessage
Example:
  ./setup/initial-setup.sh saebasol user@domain.tld
  ./setup/initial-setup.sh -h
  ./setup/initial-setup.sh --help
EOF
}
function sbs_info() {
  echo "INFO: $*"
}
function sbs_info_sub() {
  echo " - $*"
}

if [[ "${1}" == '-h' || "${1}" == '--help' ]]; then
  sbs_help
fi

sbs_info "Grabbing config..."

. ../config.sh

if [[ -z "$sbs_subuser" || -z "$sbs_email" || -z "$sbs_cf_key" ]]; then
  echo "ERROR: Please complete config.sh"
  exit 1
fi

sbs_info "Fetching fresh upgrades from upstream repository..."

apt-get update
apt-get upgrade -y

sbs_info "Installing necessary packages..."

sbs_info_sub "Installing server side utils..."
apt-get install -y git curl wget jq vim utils-linux sudo

sbs_info_sub "Installing benchmarking and stat utils..."
apt-get install -y vnstat iftop iotop htop powertop

sbs_info_sub "Installing security packages..."
apt-get install -y psad unattended-upgrades ufw iptables-persistent rkhunter chkrootkit

sbs_info_sub "Installing docker and docker-compose..."
apt-get install -y apt-transport-https ca-certificates gnupg lsb-release
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

sbs_var_compose_version=$(curl -sL "https://api.github.com/repos/docker/compose/releases/latest" | jq --raw-output '.tag_name' | grep -Eo '[0-9]+.[0-9]+.[0-9]+')
curl -L "https://github.com/docker/compose/releases/download/${sbs_var_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

adduser "$sbs_subuser" docker

sbs_info "Setting up security services..."

sbs_info "Upgrading rkhunter..."
rkhunter --update
rkhunter --propupd
sbs_info_sub "Setting up iptables rules..."
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
netfilter-persistent save
sbs_info_sub "Setting up iptables to log for other IDS services..."
iptables -A INPUT -j LOG
iptables -A FORWARD -j LOG
ip6tables -A INPUT -j LOG
ip6tables -A FORWARD -j LOG
sbs_info_sub "Setting up kernel parameters which enhances server security..."
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
sbs_info_sub "Setting up psad service..."
service rsyslog restart
cp -f ./config/psad.conf /etc/psad/psad.conf
service psad restart
psad --sig-update
psad -H
psad -R
psad --fw-analyze

sbs_info "Starting and registering services to launch at boot..."
service dockerd start
service vnstatd start
systemctl enable docker vnstat iptables psad

sbs_info "Installing xanmod to improve performance..."
echo 'deb http://deb.xanmod.org releases main' | sudo tee /etc/apt/sources.list.d/xanmod-kernel.list
wget -qO - https://dl.xanmod.org/gpg.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/xanmod-kernel.gpg add -
apt-get update
apt-get install linux-xanmod -y

sbs_info "Preparing certificates..."
sbs_info_sub "*running as $sbs_subuser*"

sudo -u "$sbs_subuser" bash -c : && _runas="sudo -u $sbs_subuser"
$_runas bash<<EOF
  # Certificates
  curl https://get.acme.sh | sh -s email=$sbs_email
  echo "export CF_Key=\"$sbs_cf_key\"" >> ~/.acme.sh/account.conf
  echo "export CF_Email=\"$sbs_email\"" >> ~/.acme.sh/account.conf
  ~/.acme.sh/acme.sh --issue --dns dns_cf -d doujinshiman.ga -d beta.doujinshiman.ga

  # Cron
  crontab -l > ~/.cronjobs
  echo "0 0 * * * \"/home/$sbs_subuser/.acme.sh\"/acme.sh --cron --home \"/home/$sbs_subuser/.acme.sh\" > /dev/null" >> ~/.cronjobs
  cron ~/.cronjobs
  rm -f ~/.cronjobs
EOF

sbs_info "Setting up docker services..."

sbs_info_sub "Preparing dependencies..."
mkdir -p ~/containers

cp -r ../docker/database $sbs_subuser_home/containers
cp -r ../docker/gateway $sbs_subuser_home/containers

ln -s $sbs_subuser_home/.acme.sh $sbs_subuser_home/containers/certs

sbs_info_sub "Preparing Saebasol/Heliotrope..."
git clone https://github.com/Saebasol/Heliotrope.git $sbs_subuser_home/containers/Heliotrope
cp -f ../docker/Heliotrope/docker-compose.yml $sbs_subuser_home/containers/Heliotrope/docker-compose.yml

sbs_info_sub "Applying permissions..."

chown -R $sbs_subuser_home:$sbs_subuser_home $sbs_subuser_home

sbs_info_sub "Starting services..."

sudo -u $sbs_subuser bash -c : && _runas="sudo -u $sbs_subuser"
$_runas bash<<EOF
  cd ~/containers/database
  docker-compose up -d
  cd ~/containers/gateway
  docker-compose up -d
  cd ~/containers/Heliotrope
  docker-compose up -d

  docker ps
EOF

sbs_info "Done! Please reboot manually."
