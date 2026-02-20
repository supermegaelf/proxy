![#c5f015](https://placehold.co/10x10/c5f015/c5f015.png) **СКРИПТ** ![#c5f015](https://placehold.co/10x10/c5f015/c5f015.png)

```bash
bash <(curl -s https://raw.githubusercontent.com/supermegaelf/proxy/main/proxy.sh)
```

![#1589F0](https://placehold.co/10x10/1589F0/1589F0.png) **ВРУЧНУЮ** ![#1589F0](https://placehold.co/10x10/1589F0/1589F0.png)



```bash
sudo apt update && apt upgrade -y
sudo apt install squid -y
sudo apt install apache2-utils -y
```

```bash
sudo tee -a /etc/sysctl.conf << 'EOF'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF
sudo sysctl -p
```

```bash
sudo apt install ufw -y
sudo ufw allow 22/tcp
sudo ufw allow 24000/tcp
sudo ufw enable
```

> [!IMPORTANT]
> Если портов несколько — добавить для каждого прокси.

Создать пользователя для прокси, заменив `user` и ввести пароль для прокси:

```bash
sudo htpasswd -c /etc/squid/passwd user
```

Выпонить, заменив `IP_1`, `IP_2`, `IP_3` ..., и т.д. на свои адреса:

```bash
cat > /etc/squid/squid.conf << 'EOF'
http_port IP_1:24000
http_port IP_2:24001
http_port IP_3:24002

acl portA localport 24000
acl portB localport 24001
acl portC localport 24002

tcp_outgoing_address IP_1 portA
tcp_outgoing_address IP_2 portB
tcp_outgoing_address IP_3 portC

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
EOF
```

Перезапустить Squid:

```bash
sudo systemctl restart squid
```
