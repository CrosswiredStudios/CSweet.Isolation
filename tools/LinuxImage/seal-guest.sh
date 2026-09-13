#!/usr/bin/env bash
# Remove temporary image-build access on the next boot, before accepting work.
set -euo pipefail
[[ ${CSWEET_GUEST_SERVICE:-} =~ ^[a-z0-9-]+\.service$ ]] || exit 2
[[ -f /etc/systemd/system/$CSWEET_GUEST_SERVICE ]] || exit 3
install -d -m 0755 /usr/lib/csweet /var/lib/csweet
cat >/usr/lib/csweet/seal-image.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
systemctl disable --now ssh.service ssh.socket
systemctl mask ssh.service ssh.socket
rm -f /home/csweet-image/.ssh/authorized_keys /etc/sudoers.d/90-csweet-image
passwd -l csweet-image
touch /var/lib/csweet/image-sealed
SCRIPT
chmod 0755 /usr/lib/csweet/seal-image.sh
cat >/etc/systemd/system/csweet-image-first-boot.service <<'UNIT'
[Unit]
Description=Remove temporary image-build access before running workloads
ConditionPathExists=!/var/lib/csweet/image-sealed
After=csweet-first-runtime-boot.service
[Service]
Type=oneshot
ExecStart=/usr/lib/csweet/seal-image.sh
RemainAfterExit=yes
UNIT
install -d -m 0755 "/etc/systemd/system/$CSWEET_GUEST_SERVICE.d"
cat >"/etc/systemd/system/$CSWEET_GUEST_SERVICE.d/image-seal.conf" <<'UNIT'
[Unit]
Requires=csweet-image-first-boot.service
After=csweet-image-first-boot.service
UNIT
touch /etc/cloud/cloud-init.disabled
apt-get clean
# Fixed build-owned paths inside the disposable image, never provider-host paths.
rm -rf /tmp/csweet-image-payload /var/lib/cloud/instances/*
sync
