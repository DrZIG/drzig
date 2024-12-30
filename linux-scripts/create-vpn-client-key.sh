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
  LOG_FILE=/tmp/create_vpn_client.log
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

log_info_highlighted "Check arguments..."
if [ $# -eq 0 ]; then
    raise_error "No arguments provided. The following are expected: CLIENT_NAME"
fi

SERVER="$1"
CLIENT_NAME="$2"
FOLDER_WITH_RESULTS=/data/yandex.disk/bluevps

log_info_pretty "Check variables availability"
FAILURES=$(check_variables_availability SERVER CLIENT_NAME)
if [ -n "$FAILURES" ]; then
    raise_error "Missing variables: $FAILURES"
fi

if ! sudo -f  /etc/openvpn/easy-rsa/easyrsa ; then
  raise_error "Required /etc/openvpn/easy-rsa/easyrsa file is not exists."
fi

cd /etc/openvpn/easy-rsa

log_info_highlighted "Generate client key"
sudo ./easyrsa gen-req "$CLIENT_NAME" nopass | sudo tee -a "$LOG_FILE" 2>&1
if ! grep -q "Private-Key and Public-Certificate-Request files created." "$LOG_FILE"; then
  raise_error "client files are not created."
fi

log_info_highlighted "Sign key with CA certificate"
sudo ./easyrsa sign-req client "$CLIENT_NAME" | sudo tee -a "$LOG_FILE" 2>&1
if ! grep -q "Certificate created at:" "$LOG_FILE"; then
  raise_error "Certificate is not created."
fi

log_info_highlighted "Verify certificate"
sudo openssl verify -CAfile pki/ca.crt "pki/issued/$CLIENT_NAME.crt" | sudo tee -a "$LOG_FILE" 2>&1
if ! grep -q "pki/issued/$CLIENT_NAME.crt: OK" "$LOG_FILE"; then
  raise_error "Verification did not succeed."
fi

log_info_highlighted "Copy certificate files"
sudo cp pki/ca.crt /etc/openvpn/client/ | sudo tee -a "$LOG_FILE" 2>&1
sudo cp "pki/issued/$CLIENT_NAME.crt" /etc/openvpn/client/ | sudo tee -a "$LOG_FILE" 2>&1
sudo cp "pki/private/$CLIENT_NAME.key" /etc/openvpn/client/ | sudo tee -a "$LOG_FILE" 2>&1

sudo tee -a "/etc/openvpn/client/$CLIENT_NAME.ovpn" > /dev/null << EOT
client
dev tun
proto udp

remote $SERVER 1194

ca ca.crt
cert $CLIENT_NAME.crt
key $CLIENT_NAME.key

cipher AES-256-CBC
auth SHA512
auth-nocache
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-256-GCM-SHA384:TLS-DHE-RSA-WITH-AES-256-CBC-SHA256:TLS-DHE-RSA-WITH-AES-128-GCM-SHA256:TLS-DHE-RSA-WITH-AES-128-CBC-SHA256

resolv-retry infinite
compress lz4
nobind
persist-key
persist-tun
mute-replay-warnings
verb 3
EOT

cd /etc/openvpn/
sudo zip -r -j "$CLIENT_NAME.zip" client/*
sudo cp "$CLIENT_NAME.zip" $FOLDER_WITH_RESULTS/
