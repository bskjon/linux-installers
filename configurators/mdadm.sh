#!/bin/bash
LOG_FILE="/tmp/configurer-mdadm.log"

echo "Starting configuration of Mdadm (Raid)"

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

    local dependencies=("mdadm")

    for package in "${dependencies[@]}"; do
        wstatus "Installing" "Installing $package"
        run apt-get -y install --no-install-recommends "$package"
        wvalidate "$package"
    done
}

configure() {
    mdadm --examine --scan
    wstatus "Configuration" "Requesting assemble"
    run mdadm --assemble --scan

    mds=$(blkid | grep "\/dev\/md[0-9]" | cut -d ":" -f 1)
    for i in $mds; do
        mdUiid=$(blkid -s UUID -o value $i;)
        mdName=$(echo $i | grep -P -o "\/dev\/md[0-9]" | cut -d "/" -f3)

        if grep -Fxq $mdUiid /etc/fstab
        then
            echo "UUID $mdUiid for $i exists in fstab"
            existingLine=$(grep -Fx "$mdUiid" /etc/fstab)
            echo "${YELLOW}$existingLine${NC}"
        else
            mkdir -p /media/$mdName
            echo "# Device $i with $mdUiid" >> /etc/fstab
            echo "UUID=$mdUiid  /media/$mdName  auto    rw,user,auto    0   0 " >> /etc/fstab
        fi
    done

    mount -a
}

updateAndInstallDependencies
configure

echo "Done!"
echo ""