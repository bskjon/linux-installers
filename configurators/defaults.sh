#!/bin/bash
LOG_FILE="/tmp/configurer-defaults.log"

echo "Starting installation and configuration of defaults"

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

    local dependencies=("tmux" "fzf")

    for package in "${dependencies[@]}"; do
        wstatus "Installing" "Installing $package"
        run apt-get -y install --no-install-recommends "$package"
        wvalidate "$package"
    done
}

IOMMU_USB=$(cat <<'EOF'
USBIOMMU() {
    for usb_ctrl in $(find /sys/bus/usb/devices/usb* -maxdepth 0 -type l); do
        pci_path="$(dirname "$(realpath "${usb_ctrl}")")";
        echo "Bus \$(cat \"\${usb_ctrl}/busnum\") --> \$(basename \$pci_path) (IOMMU group \$(basename \$(realpath \$pci_path/iommu_group)))";
        lsusb -s "\$(cat \"\${usb_ctrl}/busnum\"):";
        echo
    done
}
EOF
)

IOMMU_PCI=$(cat <<'EOF'
IOMMU() {
    shopt -s nullglob
    for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
        echo "IOMMU Group \${g##*/}:"
        for d in \$g/devices/*; do
            echo "\t\$(lspci -nns \${d##*/})"
        done
    done
}
EOF
)


bashrc_values=(
    "alias PCIIOMMU='IOMMU'"

    "alias docker-update='docker-compose pull; docker-compose up -d'"
    "alias ffinfo='ffprobe -v quiet -show_streams -print_format json -i'"
    "alias wan-ip='curl \"https://api.ipify.org?format=json\"'"

    "alias ls-size='ls -la --block-size=M'"

    "export PYTHONSTARTUP=~/.pythonrc"
    "source /usr/share/doc/fzf/examples/key-bindings.bash"
)

configure() {
    home_directory=""
    username=$(env | grep SUDO_USER | cut -d "=" -f 2)
    if [ "$username" ]; then
        
        # Finn hjemmekatalogen til brukeren
        home_directory=$(eval echo "~$username")
    else
        echo "Running as a non actionable user.."
    fi



    echo "bashrc file: $home_directory/.bashrc"
    # Sjekk og legg til IOMMU_PCI hvis den ikke finnes
    if ! grep -q "IOMMU()" "$home_directory/.bashrc"; then
        echo "$IOMMU_PCI" >> "$home_directory/.bashrc"
        echo "IOMMU_PCI-funksjonen lagt til i .bashrc"
    fi

    # Sjekk og legg til IOMMU_USB hvis den ikke finnes
    if ! grep -q "USBIOMMU()" "$home_directory/.bashrc"; then
        echo "$IOMMU_USB" >> "$home_directory/.bashrc"
        echo "IOMMU_USB-funksjonen lagt til i .bashrc"
    fi

    # Loop gjennom arrayen med bashrc-verdier
    for value in "${bashrc_values[@]}"; do
        # Sjekk om verdien allerede eksisterer i .bashrc
        if grep -q "$value" "$home_directory/.bashrc"; then
            echo "Alias/Funksjon eksisterer allerede i .bashrc: $value"
        else
            # Legg til alias/funksjon hvis den ikke finnes
            echo "$value" >> "$home_directory/.bashrc"
            echo "Alias/Funksjon lagt til i .bashrc: $value"
        fi
    done
}

updateAndInstallDependencies
configure

echo "Done!"
echo ""