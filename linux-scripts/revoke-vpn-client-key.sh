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

CLIENT_NAME="$1"

log_info_pretty "Check variables availability"
FAILURES=$(check_variables_availability CLIENT_NAME)
if [ -n "$FAILURES" ]; then
    raise_error "Missing variables: $FAILURES"
fi

if ! sudo -f  /etc/openvpn/easy-rsa/easyrsa ; then
  raise_error "Required /etc/openvpn/easy-rsa/easyrsa file is not exists."
fi

cd /etc/openvpn/easy-rsa

sudo ./easyrsa revoke "$CLIENT_NAME" | sudo tee -a "$LOG_FILE" 2>&1
sudo ./easyrsa gen-crl | sudo tee -a "$LOG_FILE" 2>&1
if ! grep -q "An updated CRL has been created:" "$LOG_FILE"; then
  raise_error "CRL file is not created."
fi

sudo cp pki/crl.pem /etc/openvpn/server/ | sudo tee -a "$LOG_FILE" 2>&1
