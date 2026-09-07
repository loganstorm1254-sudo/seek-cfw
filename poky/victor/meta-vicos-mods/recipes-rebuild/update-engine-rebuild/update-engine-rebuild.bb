DESCRIPTION = "jank update engine for rebuild"
LICENSE = "Anki-Inc.-Proprietary"
LIC_FILES_CHKSUM = "file://${COREBASE}/../victor/meta-qcom/files/anki-licenses/\
Anki-Inc.-Proprietary;md5=4b03b8ffef1b70b13d869dbce43e8f09"

inherit systemd

SRC_URI += " \
    file://update-engine-rebuild.sh \
    file://update-engine-rebuild.service \
    file://update-engine-rebuild.timer \
    file://update-engine-rebuild-victor-only.service \
    file://update-engine-rebuild-check.service \
"

S = "${UNPACKDIR}"

do_install () {
    install -d ${D}/usr/sbin
    install -d ${D}${systemd_unitdir}/system
    
    install -m 0755 ${UNPACKDIR}/update-engine-rebuild.sh ${D}/usr/sbin/update-engine-rebuild
    install -m 0644 ${UNPACKDIR}/update-engine-rebuild.service ${D}${systemd_unitdir}/system/update-engine-rebuild.service
    install -m 0644 ${UNPACKDIR}/update-engine-rebuild.timer ${D}${systemd_unitdir}/system/update-engine-rebuild.timer
    install -m 0644 ${UNPACKDIR}/update-engine-rebuild-victor-only.service ${D}${systemd_unitdir}/system/update-engine-rebuild-victor-only.service
install -m 0644 ${UNPACKDIR}/update-engine-rebuild-victor-only.service ${D}${systemd_unitdir}/system/update-engine-rebuild-check.service
}

FILES:${PN} += " \
    /usr/sbin/update-engine-rebuild \
    ${systemd_unitdir}/system/update-engine-rebuild.service \
    ${systemd_unitdir}/system/update-engine-rebuild.timer \
    ${systemd_unitdir}/system/update-engine-rebuild-victor-only.service \
    ${systemd_unitdir}/system/update-engine-rebuild-check.service \
"

SYSTEMD_SERVICE:${PN} = "update-engine-rebuild.timer"
