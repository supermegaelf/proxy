#!/bin/bash

echo "Обновляем систему и устанавливаем необходимые пакеты..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y squid apache2-utils

echo "Создаём пользователя для прокси..."
read -p "Введите имя пользователя для прокси: " proxy_user
sudo htpasswd -c /etc/squid/passwd "$proxy_user"

read -p "Сколько прокси вам нужно? " proxy_count

if ! [[ $proxy_count =~ ^[0-9]+$ ]]; then
    echo "Ошибка: введите корректное число."
    exit 1
fi

echo "Введите $proxy_count IP-адрес(а) для прокси через запятую (без пробелов):"
read -p "IP-адреса: " ip_input

IFS=',' read -r -a proxy_ips <<< "$ip_input"

if [[ ${#proxy_ips[@]} -ne $proxy_count ]]; then
    echo "Ошибка: количество IP-адресов (${#proxy_ips[@]}) не совпадает с количеством прокси ($proxy_count)."
    exit 1
fi

echo "Создаём конфигурацию Squid..."
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

# Перезапускаем Squid
sudo systemctl restart squid
