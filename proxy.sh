#!/bin/bash

#==============
# SQUID PROXY
#==============

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

readonly CHECK="✓"
readonly CROSS="✗"
readonly INFO="*"

#====================
# UTILITY FUNCTIONS
#====================

error() {
    echo -e "${RED}${CROSS}${NC} $1"
    exit 1
}

#================
# SYSTEM SETUP
#================

echo -e "${CYAN}${INFO}${NC} Updating system..."
sudo apt update -y > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1
echo -e "${GREEN}${CHECK}${NC} System updated"

echo -e "${CYAN}${INFO}${NC} Installing ubuntu-standard..."
sudo apt install -y ubuntu-standard > /dev/null 2>&1
echo -e "${GREEN}${CHECK}${NC} ubuntu-standard installed"

echo -e "${CYAN}${INFO}${NC} Installing packages..."
sudo apt install -y squid apache2-utils ufw > /dev/null 2>&1
echo -e "${GREEN}${CHECK}${NC} Packages installed"

#=================
# NETWORK SETUP
#=================

echo -e "${CYAN}${INFO}${NC} Disabling IPv6..."
sudo bash -c 'echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf'
sudo bash -c 'echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf'
sudo bash -c 'echo "net.ipv6.conf.lo.disable_ipv6=1" >> /etc/sysctl.conf'
sudo sysctl -p > /dev/null 2>&1
echo -e "${GREEN}${CHECK}${NC} IPv6 disabled"

#==============
# USER INPUT
#==============

read -p "$(echo -e "${CYAN}How many proxies do you need?${NC} ")" proxy_count

if ! [[ $proxy_count =~ ^[0-9]+$ ]]; then
    error "Enter a correct number"
fi

#==================
# FIREWALL SETUP
#==================

echo -e "${CYAN}${INFO}${NC} Configuring firewall..."
sudo ufw allow 22/tcp > /dev/null 2>&1
for ((i = 0; i < proxy_count; i++)); do
    port=$((24000 + i))
    sudo ufw allow "$port/tcp" > /dev/null 2>&1
done
echo "y" | sudo ufw enable > /dev/null 2>&1
echo -e "${GREEN}${CHECK}${NC} Firewall configured"

#=================
# PROXY SETUP
#=================

read -p "$(echo -e "${CYAN}Enter username for proxy:${NC} ")" proxy_user
sudo htpasswd -c /etc/squid/passwd "$proxy_user"

echo -e "${CYAN}Enter ${WHITE}$proxy_count${CYAN} IP address(es) for proxy, comma separated (no spaces).${NC}"
read -p "$(echo -e "${CYAN}IP address(es):${NC} ")" ip_input

IFS=',' read -r -a proxy_ips <<< "$ip_input"

if [[ ${#proxy_ips[@]} -ne $proxy_count ]]; then
    error "Number of IP addresses (${#proxy_ips[@]}) does not match number of proxies ($proxy_count)"
fi

#=====================
# SQUID CONFIGURATION
#=====================

echo -e "${CYAN}${INFO}${NC} Configuring Squid..."
config_file="/etc/squid/squid.conf"
echo "" > "$config_file"

for ((i = 0; i < proxy_count; i++)); do
    port=$((24000 + i))
    echo "http_port ${proxy_ips[i]}:$port" >> "$config_file"
    echo "acl port$((i + 1)) localport $port" >> "$config_file"
    echo "tcp_outgoing_address ${proxy_ips[i]} port$((i + 1))" >> "$config_file"
done

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

sudo systemctl restart squid > /dev/null 2>&1
echo -e "${GREEN}${CHECK}${NC} Squid configured and restarted"

echo
echo -e "${GREEN}${CHECK}${NC} Configuration is complete. Squid successfully configured for ${WHITE}$proxy_count${NC} proxy."
