#!/bin/bash

set -eu

#if [ ! "$(uname -s)" = "Linux" ]; then
#  echo "ERROR: This script is for Linux use only"
#  exit 1
#fi

set +u
if [ -n "$REMOTE_LOG" ]; then
  LOG_FILE="$REMOTE_LOG"
else
  LOG_FILE=/tmp/copy_scrypts_to_server.log
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

#TEMP_DIR=$(mktemp -d)
#sudo chmod +r+x "$TEMP_DIR"
#clean_environment() {
#  rm -rf "$TEMP_DIR";
#  echo "Log file path: $LOG_FILE"
#}
#trap clean_environment EXIT

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
  echo "Usage: $0 [-h]"
  echo "Options:"
  echo " -h                   - (Optional) print help"
  echo "Available environment variables:"
  echo " - USER               - (Optional) Username for remote connection. Default: root"
  echo " - PASSWORD           - (Required) Password for remote connection via USER"
  echo " - HOST               - (Required) Connection ip or dns"
  echo " - PORT               - (Optional) Connection port. Default: 22"
  echo " - DESTINATION_FOLDER - (Optional) folder to copy scripts. Default: '/root/' for the root user, /home/USER - for other users"
}

#log_info_highlighted "Check arguments..."
#if [ $# -eq 0 ]; then
#    raise_error "No arguments provided. The following are expected: PORT"
#fi
IS_HELP=false
while getopts ":h" val
do
  case "$val" in
    h) IS_HELP=true ;;
    *) echo "usage: $0 [-h]" >&2
       exit 1 ;;
  esac
done

if $IS_HELP ; then
  print_help
  exit 0
fi

#PORT="$1"
set +u
if [ -z "$USER" ]; then
  USER=root
fi
if [ -z "$DESTINATION_FOLDER" ]; then
  if [ "$USER" = root ]; then
    DESTINATION_FOLDER="/root"
  else
    DESTINATION_FOLDER="/home/$USER"
  fi
fi
if [ -z "$PORT" ]; then
  PORT=22
fi
set -u


log_info_highlighted "Check variables availability..."
FAILURES=$(check_variables_availability USER PASSWORD HOST DESTINATION_FOLDER PORT)
if [ -n "$FAILURES" ]; then
  print_help
  raise_error "Missing environment variables: $FAILURES"
fi

log_info_highlighted "Send files..."
#scp -i "$SSH_SECRET_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_SECRET_USER_NAME@$INSTANCE_HOST:$REMOTE_LOG $WORKSPACE/$REMOTE_LOG_FILE_NAME &>/dev/null || :
echo "$PASSWORD" | pscp -P "$PORT" "*.sh" "$USER"@"$HOST":"$DESTINATION_FOLDER/"
