#!/bin/bash

#==============
# SQUID PROXY
#==============

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

readonly CHECK="✓"
readonly CROSS="✗"
readonly INFO="*"
readonly ARROW="→"

#====================
# UTILITY FUNCTIONS
#====================

error() {
    echo -e "${RED}${CROSS}${NC} $1"
    exit 1
}

section() {
    local title="$1"
    local line
    line=$(printf '=%.0s' $(seq 1 ${#title}))
    echo
    echo -e "${GREEN}${title}${NC}"
    echo -e "${GREEN}${line}${NC}"
    echo
}

#==============
# USER INPUT
#==============

input_proxy_count() {
    echo -ne "${CYAN}How many proxies do you need? ${NC}"
    read proxy_count
    while ! [[ $proxy_count =~ ^[0-9]+$ ]]; do
        echo -e "${RED}${CROSS}${NC} Enter a correct number"
        echo
        echo -ne "${CYAN}How many proxies do you need? ${NC}"
        read proxy_count
    done
}

input_proxy_credentials() {
    echo -ne "${CYAN}Enter username for proxy: ${NC}"
    read proxy_user
    while [[ -z "$proxy_user" ]]; do
        echo -e "${RED}${CROSS}${NC} Username cannot be empty!"
        echo
        echo -ne "${CYAN}Enter username for proxy: ${NC}"
        read proxy_user
    done

    echo -ne "${CYAN}Enter password for proxy: ${NC}"
    read proxy_pass
    while [[ -z "$proxy_pass" ]]; do
        echo -e "${RED}${CROSS}${NC} Password cannot be empty!"
        echo
        echo -ne "${CYAN}Enter password for proxy: ${NC}"
        read proxy_pass
    done
}

input_proxy_ips() {
    echo -ne "${CYAN}Enter ${WHITE}$proxy_count${CYAN} IP address(es), comma separated (no spaces): ${NC}"
    read ip_input
    IFS=',' read -r -a proxy_ips <<< "$ip_input"
    while [[ ${#proxy_ips[@]} -ne $proxy_count ]]; do
        echo -e "${RED}${CROSS}${NC} Number of IP addresses (${#proxy_ips[@]}) does not match number of proxies ($proxy_count)"
        echo
        echo -ne "${CYAN}IP address(es): ${NC}"
        read ip_input
        IFS=',' read -r -a proxy_ips <<< "$ip_input"
    done
}

#================
# SYSTEM SETUP
#================

setup_system() {
    section "System Setup"
    echo -e "${CYAN}${INFO}${NC} Installing packages..."
    echo -e "${GRAY}  ${ARROW}${NC} Updating package lists"
    if ! apt-get update -y > /dev/null 2>&1; then
        error "Failed to update package list"
    fi
    echo -e "${GRAY}  ${ARROW}${NC} Upgrading packages"
    if ! apt-get upgrade -y > /dev/null 2>&1; then
        error "Failed to upgrade packages"
    fi
    echo -e "${GRAY}  ${ARROW}${NC} Installing ubuntu-standard"
    if ! apt-get install -y ubuntu-standard > /dev/null 2>&1; then
        error "Failed to install ubuntu-standard"
    fi
    echo -e "${GRAY}  ${ARROW}${NC} Installing squid, apache2-utils, ufw"
    if ! apt-get install -y squid apache2-utils ufw > /dev/null 2>&1; then
        error "Failed to install packages"
    fi
    echo -e "${GREEN}${CHECK}${NC} Packages installed successfully!"
}

#=================
# NETWORK SETUP
#=================

disable_ipv6() {
    section "Network Setup"
    echo -e "${CYAN}${INFO}${NC} Disabling IPv6..."
    echo -e "${GRAY}  ${ARROW}${NC} Writing sysctl configuration"
    bash -c 'echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf'
    bash -c 'echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf'
    bash -c 'echo "net.ipv6.conf.lo.disable_ipv6=1" >> /etc/sysctl.conf'
    echo -e "${GRAY}  ${ARROW}${NC} Applying sysctl settings"
    sysctl -p > /dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} IPv6 disabled successfully!"
}

#==================
# FIREWALL SETUP
#==================

setup_firewall() {
    section "Firewall Setup"
    echo -e "${CYAN}${INFO}${NC} Configuring firewall..."
    echo -e "${GRAY}  ${ARROW}${NC} Allowing SSH port"
    ufw allow 22/tcp > /dev/null 2>&1
    echo -e "${GRAY}  ${ARROW}${NC} Allowing proxy ports"
    for ((i = 0; i < proxy_count; i++)); do
        port=$((24000 + i))
        ufw allow "$port/tcp" > /dev/null 2>&1
    done
    echo -e "${GRAY}  ${ARROW}${NC} Enabling firewall"
    echo "y" | ufw enable > /dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Firewall configured successfully!"
}

#====================
# PROXY AUTH SETUP
#====================

setup_auth() {
    section "Proxy Authentication"
    echo -e "${CYAN}${INFO}${NC} Setting up proxy authentication..."
    echo -e "${GRAY}  ${ARROW}${NC} Creating password file for user ${WHITE}$proxy_user${NC}"
    printf '%s\n' "$proxy_pass" | htpasswd -i -c /etc/squid/passwd "$proxy_user" > /dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Authentication configured successfully!"
}

#=====================
# SQUID CONFIGURATION
#=====================

configure_squid() {
    section "Squid Configuration"
    echo -e "${CYAN}${INFO}${NC} Configuring Squid..."
    echo -e "${GRAY}  ${ARROW}${NC} Writing port and ACL rules"
    config_file="/etc/squid/squid.conf"
    echo "" > "$config_file"
    for ((i = 0; i < proxy_count; i++)); do
        port=$((24000 + i))
        echo "http_port ${proxy_ips[i]}:$port" >> "$config_file"
        echo "acl port$((i + 1)) localport $port" >> "$config_file"
        echo "tcp_outgoing_address ${proxy_ips[i]} port$((i + 1))" >> "$config_file"
    done
    echo -e "${GRAY}  ${ARROW}${NC} Writing main configuration"
    cat >> "$config_file" <<EOL
max_filedescriptors 1048576

cache deny all
via off

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
acl auth_users proxy_auth REQUIRED
http_access allow auth_users

forwarded_for off
header_access From deny all
header_access Server deny all
header_access User-Agent deny all
header_replace User-Agent Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:101.0) Gecko/20100101 Firefox/101.0
header_access Referer deny all
header_replace Referer unknown
header_access WWW-Authenticate deny all
header_access Link deny all
header_access X-Forwarded-For deny all
header_access Via deny all
header_access Cache-Control deny all
EOL
    echo -e "${GRAY}  ${ARROW}${NC} Restarting Squid service"
    systemctl restart squid > /dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Squid configured and restarted successfully!"
}

#========
# MAIN
#========

echo
echo -e "${PURPLE}===============${NC}"
echo -e "${WHITE}SQUID PROXY${NC}"
echo -e "${PURPLE}===============${NC}"

section "Configuration Input"
input_proxy_count
input_proxy_credentials
input_proxy_ips

setup_system
disable_ipv6
setup_firewall
setup_auth
configure_squid

echo
echo -e "${GREEN}${CHECK}${NC} Configuration is complete. Squid successfully configured for ${WHITE}$proxy_count${NC} proxies."
