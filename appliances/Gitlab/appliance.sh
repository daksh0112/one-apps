#!/bin/bash
set -euxo pipefail

echo "[INFO] Starting GitLab appliance setup for Ubuntu 24.04..."

# Set noninteractive frontend
export DEBIAN_FRONTEND=noninteractive

# Update and install required dependencies
apt-get update
apt-get install -y curl openssh-server ca-certificates tzdata perl

# Install Postfix for email notifications (non-interactive)
echo "postfix postfix/mailname string gitlab.local" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
apt-get install -y postfix

# Add GitLab repository and install GitLab CE
curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

# Install GitLab CE - default to localhost (you can override with EXTERNAL_URL)
EXTERNAL_URL="http://localhost" apt-get install -y gitlab-ce

# Enable and start GitLab services (just in case)
gitlab-ctl reconfigure
gitlab-ctl start

# Cleanup unnecessary packages and cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Optional: Set up gitlab root password via environment variable if needed
# echo "Setting default GitLab root password..."
# GITLAB_ROOT_PASSWORD="opennebula"
# echo "root:$GITLAB_ROOT_PASSWORD" | chpasswd

# Done
echo "[INFO] GitLab appliance setup completed."
