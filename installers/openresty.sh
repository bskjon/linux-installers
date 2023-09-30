#!/bin/bash
LOG_FILE="/tmp/install-openresty.log"

echo "Starting installation of OpenResty"

# ANSI fargekoder
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

werror() {
    echo -e "${RED}[${1}]${NC} $2"
}

wstatus() {
    echo -e "${GREEN}[${1}]${NC} $2"
}

# Funksjon for å vise en valideringsmelding
wvalidate() {
    if [ $? -eq 0 ]; then
        echo -e "${1} ${GREEN}OK!${NC}"
    else
        echo -e "${RED}Error${NC} ${1} "
        exit 1 # Avbryt skriptet ved feil
    fi
}


run() {
    > "$LOG_FILE"
    local cmd="$@"
    if ! $cmd > /dev/null 2>> "$LOG_FILE"; then
        cat $LOG_FILE
    fi
}


echo "Checking user permission"
# Sjekk om brukeren har sudo-tilgang
if [ "$(sudo -n -v 2>&1)" != "" ]; then
    # Be om sudo-tilgang
    werror "Restricted" "Trenger sudo-tilgang for å kjøre skriptet på nytt."
    exec sudo "$0" "$@"
    exit 1
fi

# Sjekk om skriptet blir kjørt med forhøyede rettigheter
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
    exit 1
fi

updateAndInstallDependencies() {
    wstatus "Maintenance" "Updating apt"
    run apt -y update
    wstatus "Maintenance" "Upgrading apt packages"
    run apt -y upgrade 

    local dependencies=("wget" "gnupg" "ca-certificates" "openssl" "curl")

    for package in "${dependencies[@]}"; do
        wstatus "Installing" "Installing $package"
        run apt-get -y install --no-install-recommends "$package"
        wvalidate "$package"
    done
}


addRepository() {
    local repo_file="/etc/apt/sources.list.d/openresty.list"
    wstatus "Repository" "Adding OpenResty repository"
    wget -O - https://openresty.org/package/pubkey.gpg | sudo apt-key add -

    echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" \
        | sudo tee -a "$repo_file" > /dev/null 2>&1
    wvalidate "OpenResty repository"
}

install() {
    local dependencies=("openresty" "certbot" "luarocks" "make" "build-essential")

    for package in "${dependencies[@]}"; do
        wstatus "Installing" "Installing $package"
        run apt-get -y install --no-install-recommends "$package"
        wvalidate "$package"
    done
}


conf_nginx="

    #user  nobody;
    worker_processes  1;

    error_log  logs/error.log;
    error_log  logs/error.log  notice;
    error_log  logs/error.log  info;

    events {
        worker_connections  1024;
    }

    http {
        include       mime.types;
        default_type  application/octet-stream;
        #access_log  logs/access.log  main;

        sendfile        on;
        #tcp_nopush     on;

        keepalive_timeout  65;
        
        include ssl.conf;
        include sites/*.conf;
    }

"

conf_ssl="
    lua_shared_dict auto_ssl 1m;
    lua_shared_dict auto_ssl_settings 64k;
    resolver 1.1.1.1 ipv6=off;

    init_by_lua_block {

    auto_ssl = (require "resty.auto-ssl").new()
    auto_ssl:set("dir", "/etc/openresty/auto-ssl")
    auto_ssl:set("allow_domain", function(domain)
        return true
    end)
    auto_ssl:init()

    }

    init_worker_by_lua_block {
    auto_ssl:init_worker()
    }


    server {
    listen 443 ssl;
    ssl_certificate_by_lua_block {
        auto_ssl:ssl_certificate()
    }
        ssl_certificate     /etc/ssl/auto/resty-auto-ssl-fallback.crt;
        ssl_certificate_key /etc/ssl/auto/resty-auto-ssl-fallback.key;
    }

    server {
    listen 80;
    location /.well-known/acme-challenge/ {
        content_by_lua_block {
        auto_ssl:challenge_server()
        }
    }
    }

    server {
    listen 127.0.0.1:8999;
    client_body_buffer_size 128k;
    client_max_body_size 128k;

    location / {
        content_by_lua_block {
        auto_ssl:hook_server()
        }
    }
    }
"

conf_certBlock="
    ssl_certificate_by_lua_block {
        auto_ssl:ssl_certificate()
    }
    ssl_certificate     /etc/ssl/auto/resty-auto-ssl-fallback.crt;
    ssl_certificate_key /etc/ssl/auto/resty-auto-ssl-fallback.key;
"


postInstall() {
    wstatus "LuaRocks" "Installing Auto SSL for OpenResty"
    run luarocks install lua-resty-auto-ssl
    wvalidate "Lua AutoSSL for OpenResty"

    wstatus "Post Install" "Creating directory /etc/ssl/auto/ to store SSL certificates"
    mkdir -p /etc/ssl/auto/
    mkdir /usr/local/openresty/nginx/conf/sites


    wstatus "Post Install" "Generating self-signed fallback certificate"
    # Generer SSL-sertifikat med vertsnavn
    HOSTNAME=$(hostname)
    run openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/CN=$HOSTNAME" \
        -keyout /etc/ssl/auto/resty-auto-ssl-fallback.key \
        -out    /etc/ssl/auto/resty-auto-ssl-fallback.crt

    
    wstatus "Configuring" "Writing new nginx.conf"
    mv /usr/local/openresty/nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf.org
    echo "$conf_nginx" > /usr/local/openresty/nginx/conf/nginx.conf
    echo "$conf_ssl" > /usr/local/openresty/nginx/conf/ssl.conf
    echo "$conf_certBlock" > /usr/local/openresty/nginx/conf/cert-block.conf
    run /usr/local/openresty/nginx/sbin/nginx -t
    wvalidate "Nginx + SSL Config"


    wstatus "Service" "Enabling OpenResty"
    run systemctl enable openresty
    wstatus "Service" "Starting OpenResty"
    systemctl start openresty

}



# Steps
updateAndInstallDependencies
addRepository
install
postInstall



echo "Done!"
