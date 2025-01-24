#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Upgrade system and install necessary packages...${NC}"
sudo apt update && sudo apt upgrade -y
sudo apt install -y squid apache2-utils

read -p "$(echo -e "${GREEN}Enter username for proxy: ${NC}")" proxy_user

if [[ -z "$proxy_user" ]]; then
    echo -e "${RED}Error: username cannot be empty.${NC}"
    exit 1
fi

echo -e "${GREEN}New password:${NC}"
echo -e "${GREEN}Re-type new password:${NC}"
sudo htpasswd -c /etc/squid/passwd "$proxy_user"

read -p "$(echo -e "${GREEN}How many proxies do you need? ${NC}")" proxy_count

if ! [[ $proxy_count =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: enter a valid number.${NC}"
    exit 1
fi

read -p "$(echo -e "${GREEN}Enter $proxy_count IP address(es) for proxy in commas (no spaces): ${NC}")" ip_input

ip_input=$(echo "$ip_input" | tr -d ' ')
IFS=',' read -r -a proxy_ips <<< "$ip_input"

if [[ ${#proxy_ips[@]} -ne $proxy_count ]]; then
    echo -e "${RED}Error: number of IP addresses (${#proxy_ips[@]}) doesn't match number of proxies ($proxy_count).${NC}"
    exit 1
fi

echo -e "${GREEN}Creating Squid configuration...${NC}"
config_file="/etc/squid/squid.conf"
echo "" > "$config_file"

for ((i = 0; i < proxy_count; i++)); do
    port=$((24000 + i))
    echo "http_port ${proxy_ips[i]}:$port" >> "$config_file"
    echo "acl port$((i + 1)) localport $port" >> "$config_file"
    echo "tcp_outgoing_address ${proxy_ips[i]} port$((i + 1))" >> "$config_file"
done

cat >> "$config_file" <<EOL

cache deny all
via off
dns_v4_first on

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

sudo systemctl restart squid

echo -e "${GREEN}Configuration is complete. Squid has been successfully configured for $proxy_count proxy.${NC}"
