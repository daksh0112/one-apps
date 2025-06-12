# ---------------------------------------------------------------------------- #
# Copyright 2018-2025, OpenNebula Project, OpenNebula Systems                  #
#                                                                              #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #

### Important notes ##################################################
#
# 'ONEAPP_SITE_HOSTNAME' must be set correctly. GitLab uses the hostname
# during its setup and in URL generation for web access, repos, etc.
#
### Important notes ##################################################

# List of contextualization parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_PASSWORD_LENGTH'    'configure' 'Default password length'                            ''
    'ONEAPP_SITE_HOSTNAME'      'configure' 'Fully qualified domain name or IP'                 ''
    'ONEAPP_GITLAB_ROOT_PASSWORD' 'configure' 'GitLab root password'                            'O|password'
    'ONEAPP_SSL_CERT'           'configure' 'SSL certificate'                                   'O|text64'
    'ONEAPP_SSL_PRIVKEY'        'configure' 'SSL private key'                                   'O|text64'
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

ONEAPP_PASSWORD_LENGTH="${ONEAPP_PASSWORD_LENGTH:-16}"
ONEAPP_SITE_HOSTNAME="${ONEAPP_SITE_HOSTNAME:-$(get_local_ip)}"
ONEAPP_GITLAB_ROOT_PASSWORD="${ONEAPP_GITLAB_ROOT_PASSWORD:-$(gen_password ${ONEAPP_PASSWORD_LENGTH})}"

### Globals ##########################################################

DEP_PKGS="curl policycoreutils openssh-server postfix firewalld git"

###############################################################################
# Service implementation
###############################################################################

service_cleanup()
{
    :
}

service_install()
{
    install_pkgs ${DEP_PKGS}
    install_gitlab
    create_one_service_metadata
    postinstall_cleanup
    msg info "INSTALLATION FINISHED"
    return 0
}

service_configure()
{
    stop_services
    configure_firewall
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

install_pkgs()
{
    msg info "Installing required packages"
    yum install -y epel-release
    yum install -y "${@}"
}

install_gitlab()
{
    msg info "Installing GitLab CE"
    curl https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.rpm.sh | bash
    EXTERNAL_URL="http://${ONEAPP_SITE_HOSTNAME}" yum install -y gitlab-ce
}

stop_services()
{
    msg info "Stopping GitLab"
    gitlab-ctl stop || true
}

enable_services()
{
    msg info "Enabling services"
    systemctl enable firewalld
}

start_gitlab()
{
    msg info "Starting GitLab"
    gitlab-ctl reconfigure
}

configure_firewall()
{
    msg info "Configuring firewall"
    systemctl start firewalld
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
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
    msg info "Cleaning up"
    yum clean all
    rm -rf /var/cache/yum
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
