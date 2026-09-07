DESCRIPTION = "Victor Cloud Services daemon"
LICENSE = "Anki-Inc.-Proprietary"                                                                   
LIC_FILES_CHKSUM = "file://${COREBASE}/../victor/meta-qcom/files/anki-licenses/\                           
Anki-Inc.-Proprietary;md5=4b03b8ffef1b70b13d869dbce43e8f09"

SERVICE_FILE = "vic-cloud.service"
# GOINSTALLER="go1.15.6.linux-amd64.tar.gz"

SRC_URI = "file://${SERVICE_FILE}"
S = "${UNPACKDIR}"
#UNPACKDIR = "${S}"

inherit systemd

DEPENDS = "pkgconfig-native"

do_install:append () {
   if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
       install -d ${D}${systemd_unitdir}/system/
       install -m 0644 ${S}/${SERVICE_FILE} -D ${D}${systemd_unitdir}/system/${SERVICE_FILE}
   fi
}

FILES:${PN} += "${systemd_unitdir}/system/"
SYSTEMD_SERVICE:${PN} = "${SERVICE_FILE}"

inherit externalsrc

EXTERNALSRC = "${WORKSPACE}/anki/vic-cloudswitch"

GID_ANKI      = '2901'
GID_CLOUD     = '888'
GID_ANKINET   = '2905'

UID_NET       = "${GID_ANKINET}"
UID_CLOUD     = "${GID_CLOUD}"

do_clean:append() {
    s = d.getVar('S')
    os.system('cd "%s" && rm -rf build/' % s)
}

run_victor() {
  export -n CCACHE_DISABLE
  export CCACHE_DIR="${HOME}/.ccache"
  env \
    -u AR \
    -u AS \
    -u BUILD_AR \
    -u BUILD_AS \
    -u BUILD_CC \
    -u BUILD_CCLD \
    -u BUILD_CFLAGS \
    -u BUILD_CPP \
    -u BUILD_CPPFLAGS \
    -u BUILD_CXX \
    -u BUILD_CXXFLAGS \
    -u BUILD_FC \
    -u CPPFLAGS \
    -u LC_ALL \
    -u LD \
    -u LDFLAGS \
    -u MAKE \
    -u NM \
    -u OBJCOPY \
    -u OBJDUMP \
    -u PATCH_GET \
    -u PKG_CONFIG_DIR \
    -u PKG_CONFIG_DISABLE_UNINSTALLED \
    -u PKG_CONFIG_LIBDIR \
    -u PKG_CONFIG_PATH \
    -u PKG_CONFIG_SYSROOT_DIR \
    -u PSEUDO_DISABLED \
    -u PSEUDO_UNLOAD \
    -u RANLIB \
    -u STRINGS \
    -u STRIP \
    -u TARGET_CFLAGS \
    -u TARGET_CPPFLAGS \
    -u TARGET_CXXFLAGS \
    -u TARGET_LDFLAGS \
    -u TOPLEVEL \
    -u WORKSPACE \
    -u base_bindir \
    -u base_libdir \
    -u base_prefix \
    -u base_sbindir \
    -u bindir \
    -u datadir \
    -u docdir \
    -u exec_prefix \
    -u includedir \
    -u infodir \
    -u libdir \
    -u libexecdir \
    -u localstatedir \
    -u mandir \
    -u nonarch_base_libdir \
    -u nonarch_libdir \
    -u oldincludedir \
    -u prefix \
    -u sbindir \
    -u servicedir \
    -u sharedstatedir \
    -u sysconfdir \
    -u systemd_system_unitdir \
    -u systemd_unitdir \
    -u systemd_user_unitdir \
    -u userfsdatadir \
    -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=$HOME PWD="${EXTERNALSRC}" \
    "$@"
}

do_compile[pseudo] = "0"
do_compile[network] = "1"

do_compile() {
    # mkdir -p "${GOPATH}"
    # mkdir -p "${GOEXEPATH}"

    # if [ ! -f "${GOEXEPATH}/bin/go" ]; then
    #    wget -P "${WORKDIR}" "https://golang.org/dl/${GOINSTALLER}"
    #    tar zxvf "${WORKDIR}/${GOINSTALLER}" -C "${GOEXEPATH}"
    # fi

    cd "${EXTERNALSRC}"
    # export GOPATH="${GOPATH}"
    # export PATH="${GOEXEPATH}/go/bin:${PATH}"
    # using system Go

    if [ ! -f "${EXTERNALSRC}/build/sherpa-shared-citrinet/.unzipped" ]; then
        wget https://github.com/kercre123/vic-cloudless/releases/download/v0.0.1/sherpa-shared-citrinet.tar.gz
        mkdir -p "${EXTERNALSRC}/build"
        tar -zxf "${EXTERNALSRC}/sherpa-shared-citrinet.tar.gz" -C "${EXTERNALSRC}"
        mv "${EXTERNALSRC}/sherpa-shared-citrinet" "${EXTERNALSRC}/build/"
        rm -f "${EXTERNALSRC}/sherpa-shared-citrinet.tar.gz"
        touch "${EXTERNALSRC}/build/sherpa-shared-citrinet/.unzipped"
    fi

    mkdir -p "${EXTERNALSRC}/build/en-US"
    wget -q --show-progress -O build/en-US/en-US.json https://github.com/Victor-Rebuild/cavalier-1.6/raw/refs/heads/main/intent-data/en-US.json

    run_victor make
}

do_install() {
    install -d ${D}/anki/bin
    install -d ${D}/anki/lib
    install -d ${D}/anki/data/cloudswitch
    install -d ${D}/anki/data/cloudswitch/sherpa
    install -d ${D}/etc/sudoers.d

    install -m 0755 ${WORKSPACE}/anki/vic-cloudswitch/build/vic-* ${D}/anki/bin/
    install -m 0644 ${WORKSPACE}/anki/vic-cloudswitch/build/lib* ${D}/anki/lib/
    install -m 0644 ${WORKSPACE}/anki/vic-cloudswitch/build/sherpa-shared-citrinet/lib/libonnxruntime.so.1 ${D}/anki/lib/
    install -m 0644 ${WORKSPACE}/anki/vic-cloudswitch/build/sherpa-shared-citrinet/lib/libsherpa-onnx-c-api.so ${D}/anki/lib/
    install -m 0644 ${WORKSPACE}/anki/vic-cloudswitch/build/sherpa-shared-citrinet/lib/libonnxruntime_providers_shared.so ${D}/anki/lib/
    cp -r ${WORKSPACE}/anki/vic-cloudswitch/build/en-US ${D}/anki/data/cloudswitch/
    cp -r ${WORKSPACE}/anki/vic-cloudswitch/build/sherpa-shared-citrinet/citrinet-256-ls ${D}/anki/data/cloudswitch/sherpa/

    install -m 0440 ${WORKSPACE}/anki/vic-cloudswitch/extra/cloud.sudoers ${D}/etc/sudoers.d/cloud
    install -m 0755 ${WORKSPACE}/anki/vic-cloudswitch/extra/setfreq ${D}/anki/bin/

    if [ "${CLOUDLESS}" = "1" ]; then
        touch ${D}/etc/forceCloudless
    fi
}

do_package_qa[noexec] = "1"

INSANE_SKIP:${PN} = " already-stripped ldflags dev-elf"
EXCLUDE_FROM_SHLIBS = "1"

FILES:${PN} += "anki/bin"
FILES:${PN} += "anki/lib"
FILES:${PN} += "anki/data/cloudswitch"
FILES:${PN} += "anki/data/cloudswitch/sherpa"
FILES:${PN} += "etc/"