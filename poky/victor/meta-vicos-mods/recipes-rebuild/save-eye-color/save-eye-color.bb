SUMMARY = "save-eye-color, used by engine to save the Rebuild Eyes colors"
DESCRIPTION = "Used by engine to save the Rebuild Eyes colors"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI = "file://save-eye-color.sh"

S = "${UNPACKDIR}"
#UNPACKDIR = "${S}"

do_install() {
    install -d ${D}${sbindir}

    install -m 0755 ${S}/save-eye-color.sh         ${D}${sbindir}/save-eye-color
}

FILES:${PN} = "${sbindir}/save-eye-color"

RDEPENDS:${PN} = "bash"
