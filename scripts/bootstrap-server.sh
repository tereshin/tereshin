#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

TARGET_USER="${1:-}"
SSH_PUBLIC_KEY="${2:-}"

if [[ -z "${TARGET_USER}" || -z "${SSH_PUBLIC_KEY}" ]]; then
  echo "Usage: $0 <target_user> <ssh_public_key>" >&2
  exit 1
fi

if ! id "${TARGET_USER}" >/dev/null 2>&1; then
  echo "User '${TARGET_USER}' not found" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get install -y ca-certificates curl gnupg lsb-release ufw fail2ban apt-transport-https software-properties-common

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
usermod -aG docker "${TARGET_USER}"

SSH_DIR="/home/${TARGET_USER}/.ssh"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
install -d -m 0700 -o "${TARGET_USER}" -g "${TARGET_USER}" "${SSH_DIR}"
touch "${AUTHORIZED_KEYS}"
chown "${TARGET_USER}:${TARGET_USER}" "${AUTHORIZED_KEYS}"
chmod 0600 "${AUTHORIZED_KEYS}"
if ! grep -qxF "${SSH_PUBLIC_KEY}" "${AUTHORIZED_KEYS}"; then
  echo "${SSH_PUBLIC_KEY}" >> "${AUTHORIZED_KEYS}"
fi

cat >/etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
EOF

sshd -t
systemctl restart ssh

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

systemctl enable --now fail2ban

if ! docker network inspect web >/dev/null 2>&1; then
  docker network create web
fi

echo "Server bootstrap finished successfully."
