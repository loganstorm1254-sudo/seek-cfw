# Seek: enable Wi-Fi boot reconnect helper
do_install:append() {
	ln -sf /usr/lib/systemd/system/seek-wifi-boot.service \
		${D}/usr/lib/systemd/system/multi-user.target.wants/seek-wifi-boot.service
}
