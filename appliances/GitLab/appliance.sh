#!/bin/bash

# ---------------------------------------------------------------------------- #
# Copyright 2018-2025, OpenNebula Project, OpenNebula Systems                  #
#                                                                              #
# Licensed under the Apache License, Version 2.0                              #
# ---------------------------------------------------------------------------- #

### Important notes ##################################################
#
# 'ONEAPP_SITE_HOSTNAME' must be set correctly. GitLab uses the hostname
# during setup and for URL generation (web UI, repos, etc).
#
### Important notes ##################################################

# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_PASSWORD_LENGTH'       'configure' 'Default password length'                            ''
    'ONEAPP_SITE_HOSTNAME'         'configure' 'Fully qualified domain name or IP'                 ''
    'ONEAPP_GITLAB_ROOT_PASSWORD'  'configure' 'GitLab root password'                              'O|password'
    'ONEAPP_SSL_CERT'              'configure' 'SSL certificate'                                   'O|text64'
    'ONEAPP_SSL_PRIVKEY'           'configure' 'SSL private key'                                   'O|text64'
)

### Appliance metadata ###############################################

ONE_SERVICE_NAME='Service GitLab - KVM'
ONE_SERVICE_VERSION='16.11.0-ce.0'
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with preinstalled GitLab Community Edition'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Preinstalled GitLab CE appliance. Automate the setup using contextualization 
variables or perform manual setup via the web interface.

Initial configuration can be customized via parameters:

$(params2md 'configure')

**NOTE**: Use a valid IP/FQDN for \`ONEAPP_SITE_HOSTNAME\`.
EOF
)

### Contextualization defaults #######################################

gen_password() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c "${1:-16}" ; echo
}

get_local_ip() {
    ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1
}

msg() {
    local level="$1"; shift
    echo "[$level] $*"
}

ONEAPP_PASSWORD_LENGTH="${ONEAPP_PASSWORD_LENGTH:-16}"
ONEAPP_SITE_HOSTNAME="${ONEAPP_SITE_HOSTNAME:-$(get_local_ip)}"
ONEAPP_GITLAB_ROOT_PASSWORD="${ONEAPP_GITLAB_ROOT_PASSWORD:-$(gen_password ${ONEAPP_PASSWORD_LENGTH})}"
ONE_SERVICE_REPORT="/root/gitlab_report.txt"

### Globals ##########################################################

DEP_PKGS="curl openssh-server ca-certificates tzdata perl postfix"

###############################################################################
# Service implementation
###############################################################################

service_cleanup()
{
    :
}

service_install()
{
    configure_postfix
    install_pkgs ${DEP_PKGS}
    install_gitlab
    create_one_service_metadata
    postinstall_cleanup
    msg info "INSTALLATION FINISHED"
    return 0
}

service_configure()
{
    configure_gitlab
    enable_services
    start_gitlab
    report_config
    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    msg info "No bootstrap action necessary for GitLab CE. Access web UI to finish setup:"
    msg info "URL: http://${ONEAPP_SITE_HOSTNAME}/"
    return 0
}

###############################################################################
# Helper Functions
###############################################################################

configure_postfix()
{
    msg info "Configuring postfix preseed (non-interactive)"
    echo "postfix postfix/mailname string ${ONEAPP_SITE_HOSTNAME}" | debconf-set-selections
    echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
}

install_pkgs()
{
    msg info "Installing required packages"
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${@}"
}

install_gitlab()
{
    msg info "Adding GitLab CE repository and installing"
    curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
    EXTERNAL_URL="http://${ONEAPP_SITE_HOSTNAME}" apt-get install -y gitlab-ce
}

enable_services()
{
    msg info "Enabling GitLab service"
    systemctl enable gitlab-runsvdir.service
}

start_gitlab()
{
    msg info "Starting GitLab"
    gitlab-ctl reconfigure
}

configure_gitlab()
{
    msg info "Applying GitLab configuration"

    echo "external_url 'http://${ONEAPP_SITE_HOSTNAME}'" > /etc/gitlab/gitlab.rb

    if [ -n "$ONEAPP_SSL_CERT" ] && [ -n "$ONEAPP_SSL_PRIVKEY" ]; then
        msg info "Enabling SSL for GitLab"
        mkdir -p /etc/gitlab/ssl
        echo "$ONEAPP_SSL_CERT" | base64 -d > /etc/gitlab/ssl/${ONEAPP_SITE_HOSTNAME}.crt
        echo "$ONEAPP_SSL_PRIVKEY" | base64 -d > /etc/gitlab/ssl/${ONEAPP_SITE_HOSTNAME}.key
        chmod 600 /etc/gitlab/ssl/*

        sed -i \
            -e "s|^external_url .*|external_url 'https://${ONEAPP_SITE_HOSTNAME}'|" \
            /etc/gitlab/gitlab.rb

        echo "nginx['redirect_http_to_https'] = true" >> /etc/gitlab/gitlab.rb
        echo "nginx['ssl_certificate'] = '/etc/gitlab/ssl/${ONEAPP_SITE_HOSTNAME}.crt'" >> /etc/gitlab/gitlab.rb
        echo "nginx['ssl_certificate_key'] = '/etc/gitlab/ssl/${ONEAPP_SITE_HOSTNAME}.key'" >> /etc/gitlab/gitlab.rb
    fi

    gitlab-ctl reconfigure
}

postinstall_cleanup()
{
    msg info "Cleaning up apt cache"
    apt-get clean
    rm -rf /var/lib/apt/lists/*
}

report_config()
{
    msg info "Saving credentials and config to: ${ONE_SERVICE_REPORT}"
    cat > "$ONE_SERVICE_REPORT" <<EOF
[GitLab Access Info]
URL      = http://${ONEAPP_SITE_HOSTNAME}/
Root PW  = ${ONEAPP_GITLAB_ROOT_PASSWORD}
EOF
    chmod 600 "$ONE_SERVICE_REPORT"
}
