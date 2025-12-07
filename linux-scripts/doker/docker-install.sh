#!/bin/bash

set +u
if [ -n "$LOG_FILE_NAME" ]; then
  LOG_FILE="$LOG_FILE_NAME"
else
  SCRIPT_NAME=$(basename "$0")
  SCRIPT_NAME_NO_EXTENSION="${SCRIPT_NAME%.*}"
  LOG_FILE=/tmp/$SCRIPT_NAME_NO_EXTENSION.log
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
  echo "ERROR: $*" >&2
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
  echo "Usage: $0 [OPTION]"
  echo "Options:"
  echo " -h, --help                   - (Optional) print help"
  echo " -c, --clean                  - (Optional) clean previous docker installations"
}

IS_HELP=false
IS_CLEAN=false
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --help|-h)
            IS_HELP=true
            shift
            ;;
        --clean|-c)
            IS_CLEAN=true
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if $IS_HELP ; then
  print_help
  exit 0
fi

log_info_pretty "Starting Docker installation..."

# Remove any old versions of Docker (clean install)
if $IS_CLEAN ; then
  log_info_highlighted "Attempting to remove any conflicting Docker packages..."
  sudo yum remove docker \
                docker-client \
                docker-client-latest \
                docker-common \
                docker-latest \
                docker-latest-logrotate \
                docker-selinux \
                docker-engine-selinux \
                docker-engine \
                -y || true
fi

# Install required packages for yum-config-manager
log_info_highlighted "Installing yum-utils and device-mapper-persistent-data..."
sudo yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2 || raise_error "Failed to install yum-utils or device-mapper-persistent-data."

# Add the Docker CE stable repository
log_info_highlighted "Adding Docker CE stable repository..."
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo || raise_error "Failed to add Docker repository."

# Install Docker Engine, containerd.io, and docker-buildx-plugin
log_info_highlighted "Installing Docker Engine, containerd.io, and docker-buildx-plugin..."
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin || raise_error "Failed to install Docker components."

# Start and enable Docker service
log_info_highlighted "Starting and enabling Docker service..."
sudo systemctl start docker || raise_error "Failed to start Docker service."
sudo systemctl enable docker || raise_error "Failed to enable Docker service."

# Add current user to the 'docker' group
# This allows running docker commands without 'sudo'
log_info_highlighted "Adding current user '$USER' to the 'docker' group..."
sudo usermod -aG docker "$USER" || raise_error "Failed to add user to docker group."

log_info_highlighted "Docker installation complete!"
log_info_highlighted "Please log out and log back in, or run 'newgrp docker' for the group changes to take effect."
log_info_highlighted "You can verify the installation by running: docker run hello-world"
