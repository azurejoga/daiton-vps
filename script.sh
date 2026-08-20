#!/bin/bash

# 0. Encerrar qualquer processo residual do QEMU
pkill -9 -f qemu-system-x86_64 2>/dev/null
sleep 1

# 1. Preparar diretório de trabalho
mkdir -p /home/daytona && cd /home/daytona
rm -f seed.img user-data

# ==========================================
# ENTRADA DE DADOS INTERATIVA
# ==========================================
clear
echo "=========================================="
echo "    CONFIGURADOR DE VM - INFINITE LABS    "
echo "=========================================="
echo ""

read -p "🔹 Digite a RAM em GB (Padrão: 32): " RAM_INPUT
RAM_GB=${RAM_INPUT:-32}

read -p "🔹 Digite os núcleos de CPU (Padrão: 16): " CPU_INPUT
CPU_CORES=${CPU_INPUT:-16}

read -p "🔹 Digite o espaço extra em Disco em GB (Padrão: 20): " DISK_INPUT
DISK_ADD=${DISK_INPUT:-20}

read -p "🔹 Digite a porta SSH do Host (Padrão: 2222): " PORT_INPUT
HOST_PORT=${PORT_INPUT:-2222}

read -p "🔹 Digite a senha do usuário Root (Padrão: root): " PASS_INPUT
ROOT_PASS=${PASS_INPUT:-root}

echo ""
echo "⚙️ Configurações selecionadas:"
echo "   - RAM: ${RAM_GB}G"
echo "   - vCPUs: ${CPU_CORES}"
echo "   - Disco Extra: +${DISK_ADD}G"
echo "   - Porta Local SSH: ${HOST_PORT}"
echo "   - Senha Root: ${ROOT_PASS}"
echo ""

# 2. Baixar imagem oficial do Ubuntu 22.04 LTS (se ainda não existir)
if [ ! -f "ubuntu22.qcow2" ]; then
  echo "📥 Baixando imagem base do Ubuntu..."
  wget -q --show-progress https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O ubuntu22.qcow2
fi

# Expandir o disco virtual com o valor digitado
echo "💾 Redimensionando disco..."
qemu-img resize ubuntu22.qcow2 +${DISK_ADD}G

# 3. Configurar Cloud-Init liberando Root + Senha no SSH
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

# 4. Gerar a ISO de inicialização (NoCloud)
cloud-localds seed.img user-data

echo "🚀 Iniciando a VM no QEMU..."
echo "👉 Conecte em outra aba via: ssh -o StrictHostKeyChecking=no root@localhost -p ${HOST_PORT}"
echo ""

# 5. Iniciar a VM via QEMU com as variáveis digitadas
qemu-system-x86_64 \
  -hda /home/daytona/ubuntu22.qcow2 \
  -m ${RAM_GB}G \
  -smp ${CPU_CORES} \
  -drive file=/home/daytona/seed.img,format=raw \
  -nographic \
  -netdev user,id=net0,hostfwd=tcp::${HOST_PORT}-:22 \
  -device e1000,netdev=net0
