#!/bin/bash

# ==========================================
# 1. MATAR E LIMPAR TUDO PREVIAMENTE
# ==========================================
echo "🧹 Limpando processos e arquivos residuais..."
pkill -9 -f qemu-system-x86_64 2>/dev/null
pkill -9 -f sshx 2>/dev/null
sleep 1

# Instalação forçada de dependências necessárias
apt-get update -y > /dev/null 2>&1
apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils wget openssh-client curl > /dev/null 2>&1

# Limpeza dos diretórios e arquivos
rm -rf /home/daytona/seed.img /home/daytona/user-data /home/daytona/.vps_env
mkdir -p /home/daytona && cd /home/daytona

# ==========================================
# 2. ENTRADA INTERATIVA DE DADOS (COM SANITIZAÇÃO)
# ==========================================
clear
echo "=========================================="
echo "    CONFIGURADOR DE VM - INFINITE LABS    "
echo "=========================================="
echo ""

read -p "🔹 Digite a RAM em GB (Padrao: 32): " RAM_INPUT
RAM_GB=$(echo "$RAM_INPUT" | tr -cd '0-9')
RAM_GB=${RAM_GB:-32}

read -p "🔹 Digite os nucleos de CPU (Padrao: 16): " CPU_INPUT
CPU_CORES=$(echo "$CPU_INPUT" | tr -cd '0-9')
CPU_CORES=${CPU_CORES:-16}

read -p "🔹 Digite o espaco extra em Disco em GB (Padrao: 20): " DISK_INPUT
DISK_ADD=$(echo "$DISK_INPUT" | tr -cd '0-9')
DISK_ADD=${DISK_ADD:-20}

read -p "🔹 Digite a porta SSH do Host (Padrao: 2222): " PORT_INPUT
HOST_PORT=$(echo "$PORT_INPUT" | tr -cd '0-9')
HOST_PORT=${HOST_PORT:-2222}

read -p "🔹 Digite a senha do usuario Root (Padrao: root): " PASS_INPUT
ROOT_PASS=${PASS_INPUT:-root}

echo ""
echo "⚙️  Configurações validadas:"
echo "   - RAM: ${RAM_GB}G"
echo "   - vCPUs: ${CPU_CORES}"
echo "   - Disco Extra: +${DISK_ADD}G"
echo "   - Porta Local SSH: ${HOST_PORT}"
echo "   - Senha Root: ${ROOT_PASS}"
echo ""

# ==========================================
# 3. PREPARAÇÃO DA IMAGEM E DISCO
# ==========================================
if [ ! -f "ubuntu22.qcow2" ]; then
  echo "📥 Baixando imagem base do Ubuntu 22.04 LTS..."
  wget -q --show-progress https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O ubuntu22.qcow2
fi

echo "💾 Redimensionando disco..."
qemu-img resize ubuntu22.qcow2 +${DISK_ADD}G > /dev/null 2>&1

# ==========================================
# 4. CONFIGURAÇÃO DO CLOUD-INIT (ROOT LIBERADO)
# ==========================================
cat <<EOF > user-data
#cloud-config
disable_root: false
ssh_pwauth: true

chpasswd:
  list: |
    root:${ROOT_PASS}
  expire: False

bootcmd:
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
  - mkdir -p /etc/ssh/sshd_config.d
  - echo "PermitRootLogin yes" > /etc/ssh/sshd_config.d/01-root.conf
  - echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config.d/01-root.conf

runcmd:
  - systemctl restart ssh || systemctl restart sshd
EOF

cloud-localds seed.img user-data > /dev/null 2>&1

# ==========================================
# 5. INICIALIZAÇÃO DA VM
# ==========================================
echo "🚀 Iniciando a VM no QEMU..."
echo "👉 Conecte em outra aba via: ssh -o StrictHostKeyChecking=no root@localhost -p ${HOST_PORT}"
echo ""

exec qemu-system-x86_64 \
  -hda /home/daytona/ubuntu22.qcow2 \
  -m ${RAM_GB}G \
  -smp ${CPU_CORES} \
  -drive file=/home/daytona/seed.img,format=raw \
  -nographic \
  -netdev user,id=net0,hostfwd=tcp::${HOST_PORT}-:22 \
  -device e1000,netdev=net0
