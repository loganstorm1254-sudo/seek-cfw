SUMMARY = "Seek Doom for Anki Vector face"
DESCRIPTION = "doomgeneric port + Freedoom IWAD for SeekOS"
LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://seek-doom \
    file://freedoom1.wad.gz \
"

S = "${WORKDIR}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/seek-doom ${D}${bindir}/seek-doom

    install -d ${D}/usr/share/seek-doom
    gzip -dc ${WORKDIR}/freedoom1.wad.gz > ${D}/usr/share/seek-doom/freedoom1.wad
    chmod 0644 ${D}/usr/share/seek-doom/freedoom1.wad
}

FILES:${PN} += "${bindir}/seek-doom /usr/share/seek-doom/*"
