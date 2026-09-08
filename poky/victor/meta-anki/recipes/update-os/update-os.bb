DESCRIPTION = "Anki developer script to update OS on robot (error-safe curl flash)"
LICENSE = "Anki-Inc.-Proprietary"
LIC_FILES_CHKSUM = "file://${COREBASE}/../victor/meta-qcom/files/anki-licenses/\
Anki-Inc.-Proprietary;md5=4b03b8ffef1b70b13d869dbce43e8f09"

SRC_URI += " \
    file://update-os.sh \
    file://rebuild-update-os.sh \
    file://unlock-manual-flash-v2.sh \
    file://fix-error-920.sh"

S = "${UNPACKDIR}"
#UNPACKDIR = "${S}"

do_install:append() {
   install -d ${D}/usr/sbin
   install -m 0700 ${UNPACKDIR}/update-os.sh ${D}/usr/sbin/update-os
   install -m 0700 ${UNPACKDIR}/rebuild-update-os.sh ${D}/usr/sbin/rebuild-update-os
   install -m 0700 ${UNPACKDIR}/unlock-manual-flash-v2.sh ${D}/usr/sbin/unlock-manual-flash-v2.sh
   install -m 0700 ${UNPACKDIR}/fix-error-920.sh ${D}/usr/sbin/fix-error-920
}

FILES:${PN} = "/usr/sbin/update-os \
               /usr/sbin/rebuild-update-os \
               /usr/sbin/unlock-manual-flash-v2.sh \
               /usr/sbin/fix-error-920"
