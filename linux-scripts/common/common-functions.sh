
function log_info() {
  set +u
  if [ "empty$LOG_FILE" == "empty" ]; then
    printf "$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n" "$1" >&2
  else
    printf "$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n" "$1" 2>&1 | tee -a "$LOG_FILE" >&2
  fi
  set -u
}

function log_info_pretty() {
  set +u
  if [ "empty$LOG_FILE" == "empty" ]; then
    printf "\n#######################################\n$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n#######################################\n" "$1" >&2
  else
    printf "\n#######################################\n$(date +"%Y-%m-%d %H:%M:%S,%3N")\t%s\n#######################################\n" "$1" 2>&1 | tee -a "$LOG_FILE" >&2
  fi
  set -u
}

function function_header() {
  set +u
  if [ "empty$LOG_FILE" == "empty" ]; then
    printf "\n####################################### %s #######################################\n" "$1" >&2
  else
    printf "\n####################################### %s #######################################\n" "$1" 2>&1 | tee -a "$LOG_FILE" >&2
  fi
  set -u
}

function raise_error() {
  EXIT_CODE=1
  EXIT_STATUS_MESSAGE="$*"

  set +u
  if [ "empty$LOG_FILE" == "empty" ]; then
    printf "$(date +"%Y-%m-%d %H:%M:%S,%3N")\tERROR: %s\n" "$*" >&2
  else
    printf "$(date +"%Y-%m-%d %H:%M:%S,%3N")\tERROR: %s\n" "$*" 2>&1 | tee -a "$LOG_FILE" >&2
  fi
  set -u

  exit 1
}

function empty_line() {
  set +u
  if [ "empty$LOG_FILE" == "empty" ]; then
    printf "\n" >&2
  else
    printf "\n" 2>&1 | tee -a "$LOG_FILE" >&2
  fi
  set -u
}

function check_variables_availability() {
  log_info_pretty "Check variables availability"
  log_info "Required variables: $*"

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

  if [ -n "$NOT_AVAILABLE" ]; then
    raise_error "Missing variables: $NOT_AVAILABLE"
  fi
}

clean_environment() {
  function_header "Clean environment"
  sudo rm -rf "$TEMP_DIR"
  any_log=$(sudo find /tmp -maxdepth 1 -type f -name "*.log" -print -quit)
  if [ -n "$any_log" ]; then
    sudo chown "$MAIN_USER" /tmp/*.log
  fi
  log_info "Log file path: $LOG_FILE"
}

dump_script_status() {
  function_header "Dump script status"

  if sudo ls "$SCRIPT_STATUS_FILE" 2> /dev/null ; then
    sudo rm -rf "$SCRIPT_STATUS_FILE"
  fi
  touch "$SCRIPT_STATUS_FILE" && sudo chown "$MAIN_USER" "$SCRIPT_STATUS_FILE" && chmod 666 "$SCRIPT_STATUS_FILE"

  log_info "EXIT_CODE=$EXIT_CODE"
  log_info "EXIT_STATUS_MESSAGE=$EXIT_STATUS_MESSAGE"

  printf "EXIT_CODE=%s\n" "$EXIT_CODE" >> "$SCRIPT_STATUS_FILE" 2>&1
  printf "EXIT_STATUS_MESSAGE=%s\n" "$EXIT_STATUS_MESSAGE" >> "$SCRIPT_STATUS_FILE" 2>&1

  log_info "Script status file path: $SCRIPT_STATUS_FILE"
}

finalize() {
  dump_script_status
  clean_environment
}
