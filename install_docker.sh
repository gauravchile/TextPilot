#!/bin/bash
# =====================================================================
# UNIVERSAL DOCKER INSTALLER (DEBIAN, RHEL, FEDORA, SUSE, AMAZON)
# Author: Gaurav Chile — Docker CE + Compose Plugin
# =====================================================================

set -e

# ---------- COLORS ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[1;36m'; WHITE='\033[1;37m'; NC='\033[0m'

# ---------- LOADING ANIMATION ----------
show_progress() {
    local msg=$1; local duration=${2:-3}
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local end_time=$((SECONDS + duration)); local progress=0
    while [ $SECONDS -lt $end_time ]; do
        for f in "${frames[@]}"; do
            printf "\r%s  %s... %d%%" "$f" "$msg" "$progress"
            sleep 0.1; progress=$((progress + RANDOM % 5))
            [ $progress -ge 99 ] && progress=99
        done
    done
    printf "\r%s... 100%%\n" "$msg"
}

# ---------- HELP ----------
show_help() {
    echo -e "${WHITE}Usage:${NC}"
    echo "  $0 --install           Install Docker CE + Compose Plugin"
    echo "  $0 --remove            Uninstall Docker completely"
    echo "  $0 --status            Show Docker service status"
    echo "  $0 --start|--stop|--restart   Control Docker service"
    echo "  $0 -h|--help           Show this help menu"
    exit 0
}

# ---------- ROOT CHECK ----------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root or with sudo.${NC}"
    exit 1
fi

# ---------- OS DETECTION ----------
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_VER=$VERSION_ID
    CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
else
    echo -e "${RED}Unable to detect OS.${NC}"
    exit 1
fi

# ---------- PACKAGE MANAGER DETECTION ----------
if command -v dnf &>/dev/null; then
    PKG_MGR=dnf; FAMILY="rhel"
elif command -v yum &>/dev/null; then
    PKG_MGR=yum; FAMILY="rhel"
elif command -v zypper &>/dev/null; then
    PKG_MGR=zypper; FAMILY="suse"
else
    PKG_MGR=apt-get; FAMILY="debian"
fi

# ---------- INSTALL DOCKER ----------
install_docker() {
    echo -e "${WHITE}############################################################################################################${NC}"
    echo -e "${WHITE}# ${CYAN} UNIVERSAL DOCKER INSTALLER — Docker CE + Compose Plugin (Cross-Platform 2025) ${WHITE}#${NC}"
    echo -e "${WHITE}############################################################################################################${NC}"

    show_progress "Updating system packages" 4
    $PKG_MGR update -y >/dev/null 2>&1 || true
    [ "$FAMILY" = "debian" ] && $PKG_MGR upgrade -y >/dev/null 2>&1 || true

    show_progress "Removing old Docker versions" 3
    $PKG_MGR remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1 || true

    show_progress "Installing prerequisites" 3
    case "$FAMILY" in
        debian)
            apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
            install -m 0755 -d /etc/apt/keyrings

            # 🔧 Safe GPG key refresh
            if [ -f /etc/apt/keyrings/docker.gpg ]; then
                echo -e "${CYAN}Refreshing existing Docker GPG key...${NC}"
                rm -f /etc/apt/keyrings/docker.gpg
            fi
            curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || {
                echo -e "${RED}Failed to fetch Docker GPG key.${NC}"
                exit 1
            }

            # 🔧 Add repository if missing
            if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
            fi

            apt-get update -y >/dev/null 2>&1
            ;;
        rhel)
            $PKG_MGR install -y yum-utils ca-certificates curl gnupg lsb-release device-mapper-persistent-data lvm2 >/dev/null 2>&1
            $PKG_MGR config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1 || true
            $PKG_MGR makecache >/dev/null 2>&1
            ;;
        suse)
            zypper refresh >/dev/null 2>&1
            ;;
        *)
            echo -e "${RED}Unsupported Linux distribution.${NC}"; exit 1;;
    esac

    show_progress "Installing Docker CE and Compose plugin" 6
    case "$FAMILY" in
        debian)
            DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;
        rhel)
            $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin --nobest >/dev/null 2>&1
            ;;
        suse)
            zypper install -y docker docker-compose >/dev/null 2>&1
            ;;
    esac

    show_progress "Starting Docker service" 3
    systemctl enable docker --now >/dev/null 2>&1
    systemctl enable containerd --now >/dev/null 2>&1

    show_progress "Verifying Docker installation" 3
    if docker --version >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}Docker and Compose plugin installed successfully!${NC}"
    else
        echo -e "${RED}Docker installation failed or Compose plugin not found.${NC}"
        exit 1
    fi

    show_progress "Configuring Docker group for non-root user" 3
    if ! getent group docker >/dev/null; then
        groupadd docker
    fi
    CURRENT_USER=$(logname 2>/dev/null || echo $SUDO_USER)
    if [ -n "$CURRENT_USER" ]; then
        sudo usermod -aG docker "$CURRENT_USER" && newgrp docker
        echo -e "${GREEN}Added user '$CURRENT_USER' to 'docker' group.${NC}"
    fi

    echo -e "\n${GREEN}✅ Docker CE + Compose plugin installation completed successfully!${NC}"
    echo -e "${CYAN}Please log out and log back in to apply group permissions.${NC}\n"
}

# ---------- UNINSTALL DOCKER ----------
remove_docker() {
    show_progress "Removing Docker" 4
    case "$FAMILY" in
        debian)
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            apt-get autoremove -y >/dev/null 2>&1
            ;;
        rhel)
            $PKG_MGR remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
            ;;
        suse)
            zypper remove -y docker docker-compose >/dev/null 2>&1
            ;;
    esac
    rm -rf /var/lib/docker /var/lib/containerd
    echo -e "${GREEN}Docker has been fully removed.${NC}"
}

# ---------- CONTROL DOCKER SERVICE ----------
case "$1" in
    --install) install_docker ;;
    --remove) remove_docker ;;
    --status) systemctl status docker --no-pager ;;
    --start) show_progress "Starting Docker" 2; systemctl start docker && echo -e "${GREEN}Docker started.${NC}" ;;
    --stop) show_progress "Stopping Docker" 2; systemctl stop docker && echo -e "${GREEN}Docker stopped.${NC}" ;;
    --restart) show_progress "Restarting Docker" 3; systemctl restart docker && echo -e "${GREEN}Docker restarted.${NC}" ;;
    -h|--help|*) show_help ;;
esac

