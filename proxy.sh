#!/bin/bash

sudo apt update -y > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1
sudo apt install -y squid apache2-utils ufw > /dev/null 2>&1

echo "Disabling IPv6..."
sudo bash -c 'echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf'
sudo bash -c 'echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf'
sudo bash -c 'echo "net.ipv6.conf.lo.disable_ipv6=1" >> /etc/sysctl.conf'
sudo sysctl -p > /dev/null 2>&1

read -p "How many proxies do you need? " proxy_count

if ! [[ $proxy_count =~ ^[0-9]+$ ]]; then
    echo "Error: enter correct number."
    exit 1
fi

sudo ufw allow 22/tcp > /dev/null 2>&1
for ((i = 0; i < proxy_count; i++)); do
    port=$((24000 + i))
    sudo ufw allow "$port/tcp" > /dev/null 2>&1
done
echo "y" | sudo ufw enable > /dev/null 2>&1

read -p "Enter username for proxy: " proxy_user
sudo htpasswd -c /etc/squid/passwd "$proxy_user"

echo "Enter $proxy_count IP address(es) for proxy, comma separated (no spaces)."
read -p "IP address(es): " ip_input

IFS=',' read -r -a proxy_ips <<< "$ip_input"

if [[ ${#proxy_ips[@]} -ne $proxy_count ]]; then
    echo "Error: number of IP addresses (${#proxy_ips[@]}) does not match number of proxies ($proxy_count)."
    exit 1
fi

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

echo "Configuration is complete. Squid successfully configured for $proxy_count proxy."
