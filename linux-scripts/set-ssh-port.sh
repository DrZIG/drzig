#!/bin/bash

set -eu

if [ ! "$(uname -s)" = "Linux" ]; then
  echo "ERROR: This script is for Linux use only"
  exit 1
fi

set +u
if [ -n "$REMOTE_LOG" ]; then
  LOG_FILE="$REMOTE_LOG"
else
  LOG_FILE=/tmp/set_ssh_port.log
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

print_help() {
  echo "Usage: ./set-ssh-port.sh \$PORT"
}

log_info_highlighted "Check arguments..."
if [ $# -eq 0 ]; then
    raise_error "No arguments provided. The following are expected: PORT"
fi

PORT="$1"

log_info_highlighted "Check variables availability..."
FAILURES=$(check_variables_availability PORT)
if [ -n "$FAILURES" ]; then
    raise_error "Missing variables: $FAILURES"
fi

log_info_highlighted "Check port number..."
if [[ ! $PORT =~ ^[0-9]+$ ]] ; then
    raise_error "Specified port $PORT contains prohibited symbols."
fi

log_info_highlighted "Check port accessibility..."
if sudo netstat -anp | grep -q "$PORT" ; then
  raise_error "Specified port $PORT is already in use."
fi

if sudo grep -Pq "^Port " /etc/ssh/sshd_config; then
  sudo sed -i -E "s/^Port .*/Port $PORT/g" /etc/ssh/sshd_config
elif sudo grep -Pq "^#Port " /etc/ssh/sshd_config; then
  sudo sed -i -E "s/^#Port .*/Port $PORT/g" /etc/ssh/sshd_config
else
  echo "Port $PORT" >> /etc/ssh/sshd_config
fi

sudo systemctl restart sshd
