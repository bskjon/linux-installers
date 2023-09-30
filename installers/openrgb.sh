#!/bin/bash¨
LOG_FILE="/tmp/install-openrgb.log"

echo "Starting installation of OpenRgb"


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

service_server="
[Unit]
Description=OpenRGB server service
[Service]
Type=simple
Restart=always
ExecStartPre=/bin/sleep 30
ExecStart=/usr/bin/openrgb --server
[Install]
WantedBy=multi-user.target
"



install() {
    mkdir -p /tmp/automated/
    wget -O /tmp/automated/openrgb.deb https://openrgb.org/releases/release_0.9/openrgb_0.9_amd64_bookworm_b5f46e3.deb
    dpkg -i /tmp/automated/openrgb.deb
    if [ $? -eq 0 ]; then
        echo -e "OpenRgb ${GREEN}OK!${NC}"
    else
        run apt install -f
        wvalidate "OpenRgb"
    fi

    which openrgb
    if [ $? -eq 0 ]; then
        echo "$service_server" > /etc/systemd/system/openrgb-server.service
        
        wstatus "Configuration" "Reloading daemon"
        run systemctl daemon-reload
        wvalidate "Reloading daemon"

        wstatus "Configuration" "Enabling OpenRgb Server Service"
        run systemctl enable openrgb-server.service
        wvalidate "Enabling OpenRgb service"

        wstatus "Configuration" "Starting OpenRgb Server Service"
        run systemctl start openrgb-server.service
        wvalidate "Started OpenRgb Service"

    else
        werror "Missing" "Could not find OpenRgb"
    fi

}



install

echo "Done!"