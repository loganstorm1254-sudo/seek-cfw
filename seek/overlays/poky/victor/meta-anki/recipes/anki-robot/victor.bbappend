# Seek: ship BLE OTA wrap as /anki/bin/update-engine so public websetup
# users never need SSH. Real C++ engine is update-engine.real.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

do_install:append() {
    WRAP="${WORKSPACE}/poky/victor/meta-anki/recipes/anki-robot/files/update-engine-wrap.sh"
    if [ ! -f "$WRAP" ]; then
        WRAP="${WORKSPACE}/seek/overlays/poky/victor/meta-anki/recipes/anki-robot/files/update-engine-wrap.sh"
    fi
    if [ -f ${D}/anki/bin/update-engine ] && [ -f "$WRAP" ]; then
        mv ${D}/anki/bin/update-engine ${D}/anki/bin/update-engine.real
        install -m 0550 "$WRAP" ${D}/anki/bin/update-engine
        chmod 0550 ${D}/anki/bin/update-engine.real
    fi
}

do_generate_victor_canned_fs_config:append() {
    echo "anki/bin/update-engine.real            ${UID_NET}    ${GID_ANKI} 0550" >> ${DEPLOY_DIR_IMAGE}/victor_canned_fs_config
}
