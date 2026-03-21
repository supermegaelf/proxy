#!/bin/bash

#==============
# 3PROXY SETUP
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

#===================
# UTILITY FUNCTIONS
#===================

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

#============
# USER INPUT
#============

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

generate_credentials() {
    proxy_user=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
    proxy_pass=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
}

input_proxy_ips() {
    echo -ne "${CYAN}Enter ${WHITE}$proxy_count${CYAN} IP address(es), comma separated: ${NC}"
    read ip_input
    IFS=',' read -r -a proxy_ips <<< "$ip_input"
    for i in "${!proxy_ips[@]}"; do
        proxy_ips[$i]=$(echo "${proxy_ips[$i]}" | tr -d ' ')
    done
    while [[ ${#proxy_ips[@]} -ne $proxy_count ]]; do
        echo -e "${RED}${CROSS}${NC} Number of IP addresses (${#proxy_ips[@]}) does not match number of proxies ($proxy_count)"
        echo
        echo -ne "${CYAN}IP address(es): ${NC}"
        read ip_input
        IFS=',' read -r -a proxy_ips <<< "$ip_input"
        for i in "${!proxy_ips[@]}"; do
            proxy_ips[$i]=$(echo "${proxy_ips[$i]}" | tr -d ' ')
        done
    done
}

#==============
# SYSTEM SETUP
#==============

setup_system() {
    section "System Setup"
    echo -e "${CYAN}${INFO}${NC} Installing packages..."
    echo -e "${GRAY}  ${ARROW}${NC} Updating package lists"
    if ! apt-get update -y > /dev/null 2>&1; then
        error "Failed to update package list"
    fi
    echo -e "${GRAY}  ${ARROW}${NC} Installing software-properties-common"
    if ! apt-get install -y software-properties-common > /dev/null 2>&1; then
        error "Failed to install software-properties-common"
    fi
    echo -e "${GRAY}  ${ARROW}${NC} Enabling universe repository"
    if ! add-apt-repository universe -y > /dev/null 2>&1; then
        error "Failed to enable universe repository"
    fi
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
    echo -e "${GRAY}  ${ARROW}${NC} Installing ufw and build dependencies"
    if ! apt-get install -y ufw build-essential curl wget > /dev/null 2>&1; then
        error "Failed to install dependencies"
    fi
    echo -e "${GREEN}${CHECK}${NC} Packages installed successfully!"
}

#================
# 3PROXY INSTALL
#================

install_3proxy() {
    section "3proxy Installation"
    echo -e "${CYAN}${INFO}${NC} Building 3proxy from source..."
    echo -e "${GRAY}  ${ARROW}${NC} Fetching latest version"
    local version
    version=$(curl -s https://api.github.com/repos/3proxy/3proxy/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
    if [[ -z "$version" ]]; then
        error "Failed to fetch 3proxy version from GitHub"
    fi
    echo -e "${GRAY}  ${ARROW}${NC} Downloading 3proxy ${version}"
    if ! wget -q "https://github.com/3proxy/3proxy/archive/refs/tags/${version}.tar.gz" -O /tmp/3proxy.tar.gz; then
        error "Failed to download 3proxy"
    fi
    echo -e "${GRAY}  ${ARROW}${NC} Compiling 3proxy"
    cd /tmp && tar xzf 3proxy.tar.gz
    cd "/tmp/3proxy-${version}"
    if ! make -f Makefile.Linux > /dev/null 2>&1; then
        error "Failed to compile 3proxy"
    fi
    cp bin/3proxy /usr/local/bin/3proxy
    chmod +x /usr/local/bin/3proxy
    echo -e "${GRAY}  ${ARROW}${NC} Creating systemd service"
    cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload > /dev/null 2>&1
    cd /root && rm -rf /tmp/3proxy.tar.gz /tmp/3proxy-*
    echo -e "${GREEN}${CHECK}${NC} 3proxy built and installed successfully!"
}

#===============
# NETWORK SETUP
#===============

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

#================
# FIREWALL SETUP
#================

setup_firewall() {
    section "Firewall Setup"
    echo -e "${CYAN}${INFO}${NC} Configuring firewall..."
    echo -e "${GRAY}  ${ARROW}${NC} Allowing SSH port"
    ufw allow 22/tcp > /dev/null 2>&1
    echo -e "${GRAY}  ${ARROW}${NC} Allowing proxy ports"
    for ((i = 0; i < proxy_count; i++)); do
        http_port=$((24000 + i))
        socks_port=$((25000 + i))
        ufw allow "$http_port/tcp" > /dev/null 2>&1
        ufw allow "$socks_port/tcp" > /dev/null 2>&1
    done
    echo -e "${GRAY}  ${ARROW}${NC} Enabling firewall"
    echo "y" | ufw enable > /dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} Firewall configured successfully!"
}

#======================
# 3PROXY CONFIGURATION
#======================

configure_3proxy() {
    section "3proxy Configuration"
    echo -e "${CYAN}${INFO}${NC} Configuring 3proxy..."
    echo -e "${GRAY}  ${ARROW}${NC} Writing main configuration"
    mkdir -p /etc/3proxy
    config_file="/etc/3proxy/3proxy.cfg"
    cat > "$config_file" <<EOL
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth strong
users ${proxy_user}:CL:${proxy_pass}
allow *
EOL
    echo -e "${GRAY}  ${ARROW}${NC} Writing port and IP configuration"
    for ((i = 0; i < proxy_count; i++)); do
        http_port=$((24000 + i))
        socks_port=$((25000 + i))
        echo "proxy -p${http_port} -i${proxy_ips[i]} -e${proxy_ips[i]}" >> "$config_file"
        echo "socks -p${socks_port} -i${proxy_ips[i]} -e${proxy_ips[i]}" >> "$config_file"
    done
    echo -e "${GRAY}  ${ARROW}${NC} Enabling and restarting 3proxy service"
    systemctl enable 3proxy > /dev/null 2>&1
    systemctl restart 3proxy > /dev/null 2>&1
    echo -e "${GREEN}${CHECK}${NC} 3proxy configured and restarted successfully!"
}

#======
# MAIN
#======

echo
echo -e "${PURPLE}=============${NC}"
echo -e "${WHITE}3PROXY SETUP${NC}"
echo -e "${PURPLE}=============${NC}"

section "Configuration Input"
input_proxy_count
input_proxy_ips
generate_credentials

setup_system
install_3proxy
disable_ipv6
setup_firewall
configure_3proxy

echo
echo -e "${PURPLE}========================${NC}"
echo -e "${GREEN}${CHECK}${NC} Installation complete"
echo -e "${PURPLE}========================${NC}"
echo
for ((i = 0; i < proxy_count; i++)); do
    http_port=$((24000 + i))
    socks_port=$((25000 + i))
    if (( proxy_count == 1 )); then
        echo -e "${CYAN}Proxy List:${NC}"
    else
        echo -e "${CYAN}Proxy $((i + 1)):${NC}"
    fi
    echo -e "${WHITE}HTTP: http://${proxy_user}:${proxy_pass}@${proxy_ips[i]}:${http_port}${NC}"
    echo -e "${WHITE}HTTPS: https://${proxy_user}:${proxy_pass}@${proxy_ips[i]}:${http_port}${NC}"
    echo -e "${WHITE}SOCKS5: socks5://${proxy_user}:${proxy_pass}@${proxy_ips[i]}:${socks_port}${NC}"
    echo
    echo -e "${CYAN}Telegram:${NC}"
    echo -e "${WHITE}SOCKS5 LINK: https://t.me/socks?server=${proxy_ips[i]}&port=${socks_port}&user=${proxy_user}&pass=${proxy_pass}${NC}"
    if (( i < proxy_count - 1 )); then
        echo
    fi
done
echo
echo -e "${CYAN}Useful Commands:${NC}"
echo -e "${WHITE}• View logs: journalctl -u 3proxy -f${NC}"
echo -e "${WHITE}• View config: cat /etc/3proxy/3proxy.cfg${NC}"
echo
