#!/usr/bin/env bash
# =============================================================================
# setup-jenkins.sh
# Instala Docker + Docker Compose e sobe o Jenkins via docker-compose.
# Compatível com: Ubuntu 20.04+, Debian 11+, Amazon Linux 2/2023, RHEL 8/9
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ─── Detecta distro ───────────────────────────────────────────────────────────
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        error "Não foi possível detectar a distribuição Linux."
    fi
}

DISTRO=$(detect_distro)
info "Distribuição detectada: $DISTRO"

# ─── Instala Docker ───────────────────────────────────────────────────────────
install_docker() {
    if command -v docker &>/dev/null; then
        info "Docker já instalado: $(docker --version)"
        return
    fi

    info "Instalando Docker..."

    case "$DISTRO" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y ca-certificates curl gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg \
                | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
                https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" \
                > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        amzn)
            yum update -y
            yum install -y docker
            # docker compose plugin para Amazon Linux
            mkdir -p /usr/local/lib/docker/cli-plugins
            curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
                -o /usr/local/lib/docker/cli-plugins/docker-compose
            chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
            ;;
        rhel|centos|rocky|almalinux)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *)
            error "Distro '$DISTRO' não suportada por este script. Instale o Docker manualmente."
            ;;
    esac

    systemctl enable --now docker
    info "Docker instalado com sucesso!"
}

# ─── Adiciona usuário atual ao grupo docker ───────────────────────────────────
add_user_to_docker() {
    if [ "$EUID" -eq 0 ]; then
        warning "Rodando como root — pulando configuração de grupo."
        return
    fi
    if ! groups "$USER" | grep -q docker; then
        info "Adicionando '$USER' ao grupo docker..."
        usermod -aG docker "$USER"
        warning "Faça logout/login ou rode 'newgrp docker' para aplicar."
    fi
}

# ─── Cria estrutura de diretórios ─────────────────────────────────────────────
JENKINS_DIR="/opt/jenkins"

create_structure() {
    info "Criando diretório $JENKINS_DIR..."
    mkdir -p "$JENKINS_DIR"

    cat > "$JENKINS_DIR/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  jenkins:
    image: jenkins/jenkins:lts
    container_name: jenkins
    restart: unless-stopped
    privileged: true
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - JAVA_OPTS=-Djenkins.install.runSetupWizard=false
    networks:
      - jenkins_net

volumes:
  jenkins_home:
    driver: local

networks:
  jenkins_net:
    driver: bridge
EOF

    info "docker-compose.yml criado em $JENKINS_DIR"
}

# ─── Sobe o Jenkins ───────────────────────────────────────────────────────────
start_jenkins() {
    info "Subindo Jenkins..."
    cd "$JENKINS_DIR"
    docker compose up -d
    info "Aguardando Jenkins iniciar (30s)..."
    sleep 30
}

# ─── Pega a senha inicial ─────────────────────────────────────────────────────
get_initial_password() {
    info "Senha inicial do Jenkins:"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null \
        || warning "Jenkins ainda iniciando. Rode depois: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ─── Resumo final ─────────────────────────────────────────────────────────────
print_summary() {
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}✅ Jenkins está rodando!${NC}"
    echo ""
    echo "  🌐 Acesso local:  http://localhost:8080"
    echo "  🌐 Acesso na rede: http://${LOCAL_IP}:8080"
    echo ""
    echo "  📋 Comandos úteis:"
    echo "     Ver logs:     docker logs -f jenkins"
    echo "     Parar:        docker compose -f $JENKINS_DIR/docker-compose.yml down"
    echo "     Reiniciar:    docker compose -f $JENKINS_DIR/docker-compose.yml restart"
    echo "     Senha admin:  docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
    echo ""
    echo "  🔌 Plugins recomendados (instale após o login):"
    echo "     - GitHub"
    echo "     - Docker Pipeline"
    echo "     - AWS Credentials"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && error "Execute como root: sudo bash setup-jenkins.sh"

install_docker
add_user_to_docker
create_structure
start_jenkins
get_initial_password
print_summary