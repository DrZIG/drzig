#!/bin/sh

set -eu

if [ ! "$(uname -s)" = "Linux" ]; then
  echo "ERROR: This script is for Linux use only"
  exit 1
fi

set +u
if [ -n "$REMOTE_LOG" ]; then
  LOG_FILE="$REMOTE_LOG"
else
  LOG_FILE=/tmp/create_vpn_server.log
fi
set -u
rm -rf "$LOG_FILE" && touch "$LOG_FILE" && chmod 777 "$LOG_FILE"

log_info() {
  printf "$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n" "$1" >> "$LOG_FILE"
}

log_info_highlighted() {
  printf "#####$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n" "$1" >> "$LOG_FILE"
}

log_info_pretty() {
  printf "\n#######################################\n$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n#######################################\n" "$1" >> "$LOG_FILE"
}

raise_error() {
  echo "ERROR: $*"
  printf "$(date +"%Y-%m-%d %H:%M:%S,%3N")\tERROR: %s\n" "$*" >> "$LOG_FILE"
  exit 1
}

TEMP_DIR=$(mktemp -d)
sudo chmod +r+x "$TEMP_DIR"
clean_environment() {
  rm -rf "$TEMP_DIR";
  echo "Log file path: $LOG_FILE"
}
trap clean_environment EXIT

check_variables_availability() {
  NOT_AVAILABLE=
  set +u
  # shellcheck disable=SC2048
  for SINGLE_VARIABLE in $*; do
    eval RESULT="\${$SINGLE_VARIABLE}" >> "$LOG_FILE" 2>&1
    if [ -z "$RESULT" ]; then
        NOT_AVAILABLE="$NOT_AVAILABLE $SINGLE_VARIABLE"
    fi
  done
  set -u

  echo "$NOT_AVAILABLE"
}

SERVER_NAME=drzig-server

log_info_pretty "Check variables availability"
FAILURES=$(check_variables_availability SERVER_NAME)
if [ -n "$FAILURES" ]; then
    raise_error "Missing variables: $FAILURES"
fi

which openvpn > /dev/null 2>&1 || log_info_pretty "Install openvpn" && sudo yum install openvpn -yq | sudo tee -a "$LOG_FILE" 2>&1
if ! sudo ls /usr/share/easy-rsa > /dev/null 2>&1; then
  log_info_pretty "Install easy-rsa" && sudo yum install easy-rsa -yq
fi

EASY_RSA_SOURCE=
log_info_highlighted "Find latest version of easy-rsa"
for folder in $(sudo ls -d /usr/share/easy-rsa/* | sort -rV) ; do
  EASY_RSA_SOURCE=$folder
  break
done

if [ -z "$EASY_RSA_SOURCE" ] ; then
  raise_error "Cannot find easy-rsa folder."
fi

log_info_highlighted "Copy original easy-rsa to the openvpn folder for configuration."
sudo rm -rf /etc/openvpn/easy-rsa
sudo mkdir /etc/openvpn/easy-rsa
sudo cp -r "$EASY_RSA_SOURCE/*" /etc/openvpn/easy-rsa

log_info_highlighted "Configure easy-rsa"
sudo tee -a /etc/openvpn/easy-rsa/vars > /dev/null << EOT
set_var EASYRSA                 "/etc/openvpn/easy-rsa"
set_var EASYRSA_PKI             "/etc/openvpn/easy-rsa/pki"
set_var EASYRSA_DN              "cn_only"
# if EASYRSA_DN == org, then the following options should be specified
#set_var EASYRSA_REQ_COUNTRY     "-"
#set_var EASYRSA_REQ_PROVINCE    "-"
#set_var EASYRSA_REQ_CITY        "-"
#set_var EASYRSA_REQ_ORG         "-"
#set_var EASYRSA_REQ_EMAIL       "-"
#set_var EASYRSA_REQ_OU          "-"
set_var EASYRSA_KEY_SIZE        4096
set_var EASYRSA_ALGO            rsa
set_var EASYRSA_CA_EXPIRE       7500
set_var EASYRSA_CERT_EXPIRE     3650
set_var EASYRSA_NS_SUPPORT      "no"
set_var EASYRSA_NS_COMMENT      "-"
set_var EASYRSA_EXT_DIR         "/etc/openvpn/easy-rsa/x509-types"
set_var EASYRSA_SSL_CONF        "/etc/openvpn/easy-rsa/openssl-easyrsa.cnf"
set_var EASYRSA_DIGEST          "sha256"
set_var EASYRSA_BATCH           "yes"
EOT

sudo chmod +x /etc/openvpn/easy-rsa/vars
cd /etc/openvpn/easy-rsa

log_info_highlighted "Initialize pki"
export EASYRSA_BATCH=1
sudo ./easyrsa clean-all | sudo tee -a "$LOG_FILE" 2>&1
sudo ./easyrsa init-pki | sudo tee -a "$LOG_FILE" 2>&1
if ! grep -q "'init-pki' complete" "$LOG_FILE"; then
  raise_error "PKI is not initialized."
fi

log_info_highlighted "Build CA certificate"
sudo mv vars /etc/openvpn/easy-rsa/pki
sudo ./easyrsa build-ca nopass | sudo tee -a "$LOG_FILE" 2>&1
if ! grep -q "CA creation complete" "$LOG_FILE"; then
  raise_error "CA certificate creation failure."
fi

log_info_highlighted "Build server key"
sudo ./easyrsa gen-req $SERVER_NAME nopass | sudo tee -a "$LOG_FILE" 2>&1
sudo ./easyrsa sign-req server $SERVER_NAME | sudo tee -a "$LOG_FILE" 2>&1
if ! grep -q "Certificate created at:" "$LOG_FILE"; then
  raise_error "Cannot build server key."
fi

log_info_highlighted "Verify certificate"
sudo openssl verify -CAfile pki/ca.crt pki/issued/$SERVER_NAME.crt
if [ "$(sudo openssl verify -CAfile pki/ca.crt pki/issued/$SERVER_NAME.crt)" != "pki/issued/$SERVER_NAME.crt: OK" ]; then
  raise_error "Verification was not successful."
fi

log_info_highlighted "Generate Diffie-Hellman key"
sudo ./easyrsa gen-dh
if ! grep -q "DH parameters of size 4096 created at:" "$LOG_FILE"; then
  raise_error "Cannot generate Diffie-Hellman key."
fi

log_info_highlighted "Copy certificate files"
sudo cp pki/ca.crt /etc/openvpn/server/
sudo cp pki/issued/$SERVER_NAME.crt /etc/openvpn/server/
sudo cp pki/private/$SERVER_NAME.key /etc/openvpn/server/
sudo cp pki/dh.pem /etc/openvpn/server/

cd /etc/openvpn/server/
log_info_highlighted "Configure OpenVPN"
sudo tee -a /etc/openvpn/server/server.conf > /dev/null << EOT
# OpenVPN Port, Protocol, and the Tun
port 1194
proto udp
dev tun

# OpenVPN Server Certificate - CA, server key and certificate
ca /etc/openvpn/server/ca.crt
cert /etc/openvpn/server/$SERVER_NAME.crt
key /etc/openvpn/server/$SERVER_NAME.key

#DH and CRL key
dh /etc/openvpn/server/dh.pem
crl-verify /etc/openvpn/server/crl.pem

# Network Configuration - Internal network
# Redirect all Connection through OpenVPN Server
server 10.5.0.0 255.255.255.0
push "redirect-gateway def1"

# Using the DNS from https://dns.watch
push "dhcp-option DNS 84.200.69.80"
push "dhcp-option DNS 84.200.70.40"

#Enable multiple clients to connect with the same certificate key
#duplicate-cn

# TLS Security
cipher AES-256-CBC
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256
auth SHA512
auth-nocache

# Other Configuration
keepalive 20 60
persist-key
persist-tun
compress lz4
daemon
user nobody
group nobody

# OpenVPN Log
log-append /var/log/openvpn.log
verb 3
EOT

log_info_highlighted "Enable port forwarding"
if ! sudo grep -Pq "^net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
  if sudo grep -Pq "^net.ipv4.ip_forward " /etc/sysctl.conf; then
    sudo sed -i -E "s/^net.ipv4.ip_forward .*/net.ipv4.ip_forward = 1/g" /etc/sysctl.conf
  elif sudo grep -Pq "^#net.ipv4.ip_forward " /etc/sysctl.conf; then
    sudo sed -i -E "s/^#net.ipv4.ip_forward .*/net.ipv4.ip_forward = 1/g" /etc/sysctl.conf
  else
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
  fi
fi
sudo sysctl -p

log_info_pretty "Configure Firewalld"
if which firewall-cmd > /dev/null 2>&1 ; then
  log_info_highlighted "Add the OpenVPN service to the 'public' and 'trusted' firewall zone"
  sudo firewall-cmd --permanent --add-service=openvpn | sudo tee -a "$LOG_FILE" 2>&1
  sudo firewall-cmd --permanent --zone=trusted --add-service=openvpn | sudo tee -a "$LOG_FILE" 2>&1

  log_info_highlighted "add the 'tun0' to the 'trusted' zone"
  sudo firewall-cmd --permanent --zone=trusted --add-interface=tun0 | sudo tee -a "$LOG_FILE" 2>&1

  log_info_highlighted "Enable 'MASQUERADE' on the default 'public' zone firewalld"
  sudo firewall-cmd --permanent --add-masquerade | sudo tee -a "$LOG_FILE" 2>&1

  log_info_highlighted "Enable NAT for OpenVPN internal IP address '10.5.0.0/24' to the external IP address 'SERVERIP'."
  SERVERIP=$(ip route get 1.1.1.1 | awk 'NR==1 {print $(NF-2)}')
  sudo firewall-cmd --permanent --direct --passthrough ipv4 -t nat -A POSTROUTING -s 10.8.0.0/24 -o $SERVERIP -j MASQUERADE | sudo tee -a "$LOG_FILE" 2>&1

  log_info_highlighted "Restart firewalld"
  sudo firewall-cmd --reload | sudo tee -a "$LOG_FILE" 2>&1
fi

sudo systemctl start openvpn-server@server
sudo systemctl enable openvpn-server@server

# to check the port:
# netstat -plntu
