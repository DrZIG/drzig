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
  LOG_FILE=/tmp/prepare_instance.log
fi
set -u
rm -rf "$LOG_FILE" && touch "$LOG_FILE" && chmod 777 "$LOG_FILE"

log_info() {
  printf "$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n" "$1" >> "$LOG_FILE"
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

#log_info_pretty "Check variables availability"
#FAILURES=$(check_variables_availability ARTIFACTS_PATH INSTANCE_HOST)
#if [ -n "$FAILURES" ]; then
#    raise_error "Missing variables: $FAILURES"
#fi

which netstat > /dev/null 2>&1 || log_info_pretty "Install net-tools" && sudo yum install net-tools -yq | sudo tee -a "$LOG_FILE" 2>&1
which zip > /dev/null 2>&1 || log_info_pretty "Install zip" && sudo yum install zip -yq | sudo tee -a "$LOG_FILE" 2>&1

if ! which firewall-cmd > /dev/null 2>&1 ; then
  log_info_pretty "Install FirewallD"
  sudo yum install firewalld -yq | sudo tee -a "$LOG_FILE" 2>&1

  sudo systemctl start firewalld
  sudo systemctl enable firewalld

  # firewall-cmd --list-all
  sudo firewall-cmd --set-default-zone=external
  sudo firewall-cmd --zone=external --change-interface=eth0

  # all services:
  #   ls /usr/lib/firewalld/services/
  #   firewall-cmd --get-services
  sudo firewall-cmd --zone=external --permanent --add-service=ssh
  sudo firewall-cmd --zone=external --permanent --add-service=cockpit
  sudo firewall-cmd --zone=external --permanent --add-service=dhcpv6-client
  sudo firewall-cmd --zone=external --permanent --add-service=openvpn

  sudo firewall-cmd --zone=external --permanent --add-port=56777/tcp  # ssh
  sudo firewall-cmd --zone=external --permanent --add-port=9091/tcp  # transmission
  sudo firewall-cmd --zone=external --permanent --add-port=51413/tcp
  sudo firewall-cmd --zone=external --permanent --add-port=51515/tcp
  sudo firewall-cmd --zone=external --permanent --add-port=1194/udp  # openvpn

  sudo firewall-cmd --reload
fi
