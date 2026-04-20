#!/usr/bin/env bash

SCRIPT_STATUS_FILE=/tmp/script-status.out

# Exit codes:
# 0 - success
# 1 - failure
# 2 - warning
[ "empty$EXIT_CODE" == empty ] && EXIT_CODE=0
[ "empty$EXIT_STATUS_MESSAGE" == empty ] && EXIT_STATUS_MESSAGE=

if [ ! "$(uname -s)" = "Linux" ]; then
  EXIT_STATUS_MESSAGE="ERROR: This script is for Linux use only"
  EXIT_CODE=1

  echo "$EXIT_STATUS_MESSAGE"
  exit $EXIT_CODE
fi

source "$CURRENT_SCRIPT_DIRECTORY"/common/common-functions.sh

if [ -z "$LOG_FILE" ] ; then
    if [ -n "$REMOTE_LOG" ]; then
        LOG_FILE="$REMOTE_LOG"
    elif [ -n "$PROG" ]; then
        LOG_FILE="$PROG"  # test-name.sh
        LOG_FILE=${PROG/.sh/}
        LOG_FILE="/tmp/${LOG_FILE/-/_}_log.log"  # test_name_log.log
    else
        raise_error "Cannot define log file."
    fi
    if sudo ls "$LOG_FILE" 2> /dev/null ; then
      rm -rf "$LOG_FILE"
    fi
fi
touch "$LOG_FILE" && chmod 666 "$LOG_FILE"

# TODO: implement this to get rid of extra writing log calls on important lines
# test -t 1 && {  exec $0 "$@" 2>&1 |  tee -a "$LOG_FILE"; exit; }

# print current script name at the beginning
[ "empty$PROG" != empty ] && function_header "$PROG"

set +u
if [ -z "$TEMP_DIR" ]; then
  TEMP_DIR=$(mktemp -d)
  sudo chmod 777 "$TEMP_DIR"
fi

OS_NAME=$(grep -E '^NAME=' /etc/os-release)
OS_NAME="${OS_NAME:6:-1}" # e.g. Amazon Linux, Red Hat Enterprise Linux
OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release)
OS_VERSION="${OS_VERSION:12:-1}" # e.g. 24.04
MAIN_USER=$USER

trap finalize EXIT

set -eu
