#!/usr/bin/env bash

# A very jank auto update solution for 1.6-rebuild

logger -t rebuild-auto-updater "Starting 1.6-rebuild auto update service"

# Build ids
DEV_BUILD_ID=d
OSKR_BUILD_ID=oskr
PROD_BUILD_ID=

# Essential things for this to work
BUILDINF="$(cat /build.prop)"
CMDLINE="$(cat /proc/cmdline)"
CURRENT_VERSION=$(getprop ro.anki.version)
INDEV_OR_RELEASE="$(cat /etc/rebuild-dev-or-indev)"
REBUILD_URL="http://http.anki2.ca/otas/1.6-rebuild"
VERBOSE=0

function checkIfUpdatesAreBlocked() {
    if [ -f /run/rebuild-updated ]; then
        echo "An update is already pending, waiting until nightly reboot"
        logger -t rebuild-auto-updater "An update is already pending, waiting until nightly reboot"
        exit 0
    else
        echo "No updates pending, continuing..."
        logger -t rebuild-auto-updater "No updates pending, continuing..."
    fi

    if [ -d /anki-devtools ]; then
        echo "Build has been deployed to, not auto updating"
        logger -t rebuild-auto-updater "Build has been deployed to, not auto updating"
        exit 0
    else
        echo "Build is stock, auto updates allowed"
        logger -t rebuild-auto-updater "Build is stock, auto updates allowed"
    fi

    if [ -f /data/data/user-do-not-auto-update ] || [ -f /etc/do-not-auto-update ]; then
        echo "Auto updates disabled, falling out"
        logger -t rebuild-auto-updater "Auto updates disabled, falling out"
        exit 0
    else
        echo "Auto updates are not disabled, continuing with updating"
        logger -t rebuild-auto-updater "Auto updates are not disabled, continuing with updating"
    fi
}

# Auto updates are enabled, clear to continue
function checkForUpdate () {
    if [ ${INDEV_OR_RELEASE} == indev ]; then
        if [ $VERBOSE = 1 ]; then
            echo "Indev ota detected, downloading from indev stack"
        fi
        logger -t rebuild-auto-updater "Indev ota detected, downloading from indev stack"
        TARGET_VERSION=$(curl -s -s $REBUILD_URL/indev/latest)
        FORCE_INSTALL=$(curl -s $REBUILD_URL/indev/force_install)
        INDEV=1
    elif [ ${INDEV_OR_RELEASE} == release ]; then
        if [ $VERBOSE = 1 ]; then
            echo "Release ota detected, downloading from Release stack"
        fi
        logger -t rebuild-auto-updater "Release ota detected, downloading from Release stack"
        TARGET_VERSION=$(curl -s $REBUILD_URL/release/latest)
        FORCE_INSTALL=$(curl -s $REBUILD_URL/release/force_install)
        RELEASE=1
    elif [ ${INDEV_OR_RELEASE} == internal ]; then
        echo "Internal build, DON'T UPDATE"
        logger -t rebuild-auto-updater "Internal build, DON'T UPDATE"
        touch /run/rebuild/dont-need-update
        exit 1
    else
        echo "Not indev, release, or internal, exiting"
        logger -t rebuild-auto-updater "Not indev, release, or internal, exiting"
        exit 1
    fi

    if [ $VERBOSE = 1 ]; then
        echo "Checking active slot"
    fi
    logger -t rebuild-auto-updater "Checking active slot"
    if [[ ${CMDLINE} == *"androidboot.slot_suffix=_b"* ]]; then
        if [ $VERBOSE = 1 ]; then
            echo "Current slot is b, update will install to a."
        fi
        logger -t rebuild-auto-updater "Current slot is b, update will install to a."
        INSTALL_SLOT=a
    else
        if [ $VERBOSE = 1 ]; then
            echo "Current slot is a, update will install to b."
        fi
        logger -t rebuild-auto-updater "Current slot is a, update will install to b."
        INSTALL_SLOT=b
    fi


    if [ $VERBOSE = 1 ]; then
        echo "Current firmware version: $CURRENT_VERSION"
    fi
    logger -t rebuild-auto-updater "Current firmware version: $CURRENT_VERSION"

    if [ $VERBOSE = 1 ]; then
        echo "Target update version is $TARGET_VERSION"
    fi
    logger -t rebuild-auto-updater "Target update version is $TARGET_VERSION"

    if [[ ${CURRENT_VERSION} == *$DEV_BUILD_ID ]]; then
        if [ $VERBOSE = 1 ]; then
            echo "Build type is dev"
        fi
        logger -t rebuild-auto-updater "Build type is dev"
        CURRENT_BUILD_ID=d
        DEV=1
    elif [[ ${CURRENT_VERSION} == *$OSKR_BUILD_ID ]]; then
        if [ $VERBOSE = 1 ]; then
            echo "Build type is OSKR"
        fi
        logger -t rebuild-auto-updater "Build type is OSKR"
        CURRENT_BUILD_ID=oskr
        OSKR=1
    else
        if [ $VERBOSE = 1 ]; then
            echo "Build type is production"
        fi
        logger -t rebuild-auto-updater "Build type is production"
        CURRENT_BUILD_ID=
        PROD=1
    fi

    if [[ $CURRENT_VERSION == $TARGET_VERSION$CURRENT_BUILD_ID ]]; then
        if [[ $FORCE_INSTALL == 1 ]]; then
            if [ $VERBOSE = 1 ]; then
                echo "Force install set to 1 on server, must be a very important reason why"
            fi
            logger -t rebuild-auto-updater "Force install set to 1 on server, must be a very important reason why"
            rm /run/rebuild/dont-need-update
            touch /run/rebuild/needs-update
        else
            echo "Rebuild up to date, exiting"
            logger -t rebuild-auto-updater "Rebuild up to date, exiting"
            rm -f /run/rebuild/needs-update
            rm -f /run/rebuild/target-ver
            touch /run/rebuild/dont-need-update
            exit 0
        fi
    else 
        echo "Rebuild needs updating"
        rm -f /run/rebuild/dont-need-update
        touch /run/rebuild/needs-update
        echo -n $TARGET_VERSION$CURRENT_BUILD_ID > /run/rebuild/target-ver
    fi
}

function install-update() {
    if [ $VERBOSE = 1 ]; then
        echo "Installing ota update to system slot $INSTALL_SLOT"
    fi
    logger -t rebuild-auto-updater "Installing ota update to system slot $INSTALL_SLOT"
    if [[ ${DEV} = 1 ]]; then
        if [[ ${INDEV} = 1 ]]; then
            FINAL_REBUILD_URL=$REBUILD_URL/indev/dev/vicos-$TARGET_VERSION$CURRENT_BUILD_ID.ota
        elif [[ ${RELEASE} = 1 ]]; then
            FINAL_REBUILD_URL=$REBUILD_URL/release/dev/vicos-$TARGET_VERSION$CURRENT_BUILD_ID.ota
        fi
    elif [[ ${OSKR} = 1 ]]; then
        if [[ ${INDEV} = 1 ]]; then
            FINAL_REBUILD_URL=$REBUILD_URL/indev/oskr/vicos-$TARGET_VERSION$CURRENT_BUILD_ID.ota
        elif [[ ${RELEASE} = 1 ]]; then
            FINAL_REBUILD_URL=$REBUILD_URL/release/oskr/vicos-$TARGET_VERSION$CURRENT_BUILD_ID.ota
        fi
    elif [[ ${PROD} = 1 ]]; then
        if [[ ${INDEV} = 1 ]]; then
            FINAL_REBUILD_URL=$REBUILD_URL/indev/prod/vicos-$TARGET_VERSION$CURRENT_BUILD_ID.ota
        elif [[ ${RELEASE} = 1 ]]; then
            FINAL_REBUILD_URL=$REBUILD_URL/release/prod/vicos-$TARGET_VERSION$CURRENT_BUILD_ID.ota
        fi
    fi

    if [ $VERBOSE = 1 ]; then
        echo "Update URL $FINAL_REBUILD_URL"
    fi
    logger -t rebuild-auto-updater "Update URL $FINAL_REBUILD_URL"
    /sbin/rebuild-update-os $FINAL_REBUILD_URL

    sync
    echo

    if [ $VERBOSE = 1 ]; then
      echo "Update Done"
    fi
    logger -t rebuild-auto-updater "Update Done"
}

if [[ $1 = -v ]]; then
    VERBOSE=1
fi

mkdir -p /run/rebuild/

if [[ $1 = -v ]]; then
    VERBOSE=1
fi

if [[ $1 = -c ]]; then
    checkForUpdate
    exit 0
fi

checkIfUpdatesAreBlocked
checkForUpdate
install-update

if [[ $1 = -r ]]; then
    reboot -f
fi

exit 0
