SUMMARY = "Seek Doom for Anki Vector face"
DESCRIPTION = "doomgeneric port + Freedoom IWAD for SeekOS"
LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = " \
    file://seek-doom \
    file://freedoom1.wad.gz \
"

S = "${UNPACKDIR}"
#UNPACKDIR = "${S}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/seek-doom ${D}${bindir}/seek-doom

    # bitbake auto-decompresses *.gz from SRC_URI into UNPACKDIR
    install -d ${D}/usr/share/seek-doom
    install -m 0644 ${UNPACKDIR}/freedoom1.wad ${D}/usr/share/seek-doom/freedoom1.wad
}

FILES:${PN} += "${bindir}/seek-doom /usr/share/seek-doom/*"
