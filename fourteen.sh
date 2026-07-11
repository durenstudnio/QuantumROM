#!/bin/bash

if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <STOCK_DEVICE> <TARGET_DEVICE> <TARGET_DEVICE_CSC> <TARGET_DEVICE_IMEI> <OUTPUT_FILESYSTEM> [VERSION]"
    exit 1
fi

VERSION="1"
# Jeśli przekazano 6. argument, użyj go jako wersji firmware (opcjonalne)
if [ "$#" -eq 6 ]; then
    VERSION="$6"
fi

# Device info
export STOCK_DEVICE="$1"
export TARGET_DEVICE="$2"
export TARGET_DEVICE_CSC="$3"
export TARGET_DEVICE_IMEI="$4"
export OUTPUT_FILESYSTEM="$5"

# Directories
export FIRM_DIR="$(pwd)/FW"
export OUT_DIR="$(pwd)/OUT"
export WORK_DIR="$(pwd)/WORK"
export APKTOOL="$(pwd)/bin/java/apktool.jar"
export DEVICES_DIR="$(pwd)/QuantumROM/Devices"
export VNDKS_COLLECTION="$(pwd)/QuantumROM/vndks"
export BUILD_PARTITIONS="product,system_ext,system"

# Check if STOCK_DEVICE is supported
if [ "$STOCK_DEVICE" != "None" ]; then
    echo "Checking if $STOCK_DEVICE is supported..."
    # Pobieramy listę assets i sprawdzamy czy plik istnieje
    SUPPORTED=$(curl -fsSL "https://api.github.com/repos/SN-Abdullah-Al-Noman/QuantumROM/releases/tags/QuantumROM_Devices" | \
    jq -r '.assets[].name' | grep -w "${STOCK_DEVICE}.zip")

    if [ -z "$SUPPORTED" ]; then
        echo "❌ $STOCK_DEVICE is not supported by this tool."
        exit 1
    else
        echo "$STOCK_DEVICE is supported."
    fi
fi

# Download STOCK_DEVICE config zip if missing
if [ ! -f "$(pwd)/QuantumROM/Devices/${STOCK_DEVICE}.zip" ]; then
    echo "Downloading config for $STOCK_DEVICE..."
    if curl -fsSL --connect-timeout 5 https://www.google.com >/dev/null; then
        wget --no-check-certificate \
            "https://github.com/SN-Abdullah-Al-Noman/QuantumROM/releases/download/QuantumROM_Devices/${STOCK_DEVICE}.zip" \
            -O "$(pwd)/QuantumROM/Devices/${STOCK_DEVICE}.zip"
    else
        rm -rf "$(pwd)/QuantumROM/Devices/${STOCK_DEVICE}.zip"
        echo "- No internet connection available. Unable to download: ${STOCK_DEVICE}.zip"
        exit 1
    fi
fi

# Extract config
if [ -f "${DEVICES_DIR}/${STOCK_DEVICE}.zip" ]; then
    rm -rf "${DEVICES_DIR}/${STOCK_DEVICE}"
    mkdir -p "${DEVICES_DIR}/${STOCK_DEVICE}"
    unzip -oq "${DEVICES_DIR}/${STOCK_DEVICE}.zip" -d "${DEVICES_DIR}/${STOCK_DEVICE}"
fi

# Source scripts
source "$(pwd)/scripts/debloat.sh"
source "$(pwd)/scripts/QuantumRom.sh"

# Download Firmware with specific VERSION
echo "Downloading Firmware for $TARGET_DEVICE (Version: $VERSION)..."
DOWNLOAD_FIRMWARE "$TARGET_DEVICE" "$TARGET_DEVICE_CSC" "$TARGET_DEVICE_IMEI" "$FIRM_DIR" "$VERSION"

EXTRACT_FIRMWARE "$FIRM_DIR/$TARGET_DEVICE"
EXTRACT_SUPER_IMG "$FIRM_DIR/$TARGET_DEVICE"
EXTRACT_FIRMWARE_IMG "$FIRM_DIR/$TARGET_DEVICE" "all"

INSTALL_FRAMEWORK "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework/framework-res.apk"
DECOMPILE "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework/services.jar" "$WORK_DIR"

DECODE_OMC "$FIRM_DIR/$TARGET_DEVICE" "$WORK_DIR"
DEBLOAT "$FIRM_DIR/$TARGET_DEVICE"

APPLY_STOCK_CONFIG "$FIRM_DIR/$TARGET_DEVICE"

PATCH_SELINUX "$FIRM_DIR/$TARGET_DEVICE"
DISABLE_SECURITY "$FIRM_DIR/$TARGET_DEVICE"
ADD_SAMSUNG_FLAGSHIP_APPS "$FIRM_DIR/$TARGET_DEVICE"
APPLY_CUSTOM_FEATURES "$FIRM_DIR/$TARGET_DEVICE"

PATCH_FLAG_SECURE "$WORK_DIR/services"
PATCH_SECURE_FOLDER "$WORK_DIR/services"

RECOMPILE "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework" "$WORK_DIR/services" "$WORK_DIR"
mv -f "$WORK_DIR"/*.jar "$FIRM_DIR/$TARGET_DEVICE/system/system/framework/"

PATCH_BT_LIB "$FIRM_DIR/$TARGET_DEVICE" "$WORK_DIR"

B_ID="$(grep -m1 '^ro.system.build.id=' "$FIRM_DIR/$TARGET_DEVICE/system/system/build.prop" | cut -d= -f2 | tr -d '\r')"
B_V="$(grep -m1 '^ro.system.build.version.incremental=' "$FIRM_DIR/$TARGET_DEVICE/system/system/build.prop" | cut -d= -f2 | tr -d '\r')"
BUILD_PROP "$FIRM_DIR/$TARGET_DEVICE" "system" "ro.build.display.id" "${B_ID} ${B_V} V-${VERSION}: Built with Quantum Tools"
BUILD_PROP "$FIRM_DIR/$TARGET_DEVICE" "product" "ro.build.display.id" "${B_ID} ${B_V} V-${VERSION}: Built with Quantum Tools"

BUILD_IMG "$FIRM_DIR/$TARGET_DEVICE" "all" "$OUTPUT_FILESYSTEM" "$OUT_DIR"