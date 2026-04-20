#!/usr/bin/env bash

set -e

PROG=$(basename $0)
CURRENT_SCRIPT_DIRECTORY=$(dirname "$(realpath "$0")")

source "$CURRENT_SCRIPT_DIRECTORY"/common/init.sh

# Define script variables
#set +u
#set -u
usage()
{
 cat << EOF

  Script to set port for ssh connection.

  USAGE: $ ./${PROG} [OPTIONS]

  OPTIONS:

    -h               - Help usage
    -p, --port=PORT  - Specific port to use for ssh connection. Can be set using PORT environment variable.
                       Example: "22"

  EXAMPLES:

    * Show this help message

      $ ./${PROG} -h

    * Set port 22

      $ ./${PROG} --port=22

EOF
}

log_info_pretty "Parse script parameters"
VALID_ARGS=$(getopt -o hp: --long help,port: -- "$@")
eval set -- "$VALID_ARGS"

while true; do
    case "$1" in
        -h | --help)
            log_info "Found '-h (help)' option"
            usage
            exit 0
            ;;
        -p | --port)
            log_info "Found '-p (port)' argument."
            PORT="$2"
            shift 2  # Shift past the option and its argument
            ;;
        --) # End of options marker
            shift
            break
            ;;
        *) log_info "Found unrecognized option '$1'"
            usage
            exit 1
            ;;
    esac
done

check_variables_availability PORT

log_info_pretty "Script parameters:"
log_info "PORT=$PORT"

log_info_pretty "Check port number..."
if [[ ! $PORT =~ ^[0-9]+$ ]] ; then
    raise_error "Specified port $PORT contains prohibited symbols."
fi

log_info_pretty "Check port accessibility..."
if sudo netstat -anp | grep -q "$PORT" ; then
  raise_error "Specified port $PORT is already in use."
fi

if [[ "$OS_NAME" == "Ubuntu" ]] && (( ${OS_VERSION%%.*} >= 24 )); then
  log_info "Ubuntu version greater than 24. Use ssh.socket service"
  sudo mkdir -p /etc/systemd/system/ssh.socket.d
  cat >/etc/systemd/system/ssh.socket.d/listen.conf <<EOF
[Socket]
ListenStream=
ListenStream=$PORT
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart ssh.socket
else
  log_info "Update sshd service service"
  if sudo grep -Pq "^Port " /etc/ssh/sshd_config; then
    log_info "'Port' setting is found in /etc/ssh/sshd_config"
    sudo sed -i -E "s/^Port .*/Port $PORT/g" /etc/ssh/sshd_config
  elif sudo grep -Pq "^#Port " /etc/ssh/sshd_config; then
    log_info "Commented 'Port' setting is found in /etc/ssh/sshd_config"
    sudo sed -i -E "s/^#Port .*/Port $PORT/g" /etc/ssh/sshd_config
  else
    log_info "Port setting is NOT found in /etc/ssh/sshd_config"
    echo "Port $PORT" >> /etc/ssh/sshd_config
  fi

  sudo systemctl restart sshd
fi
log_info_pretty "Port was updated successfully."
