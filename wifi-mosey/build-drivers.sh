#!/usr/bin/env bash
# Copyright (c) 2026 Rezoss
# SPDX-License-Identifier: GPL-3.0-or-later
set -Eeuo pipefail
PACKAGE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
KERNEL=$(realpath "${1:?kernel source directory required}")
DEST=$(realpath -m "${2:?output directory required}")
KOUT="$KERNEL/out"
CLANG_DIR="${CLANG_DIR:-$HOME/tools/google-clang}"
export PATH="$CLANG_DIR/bin:$PATH" CCACHE_DISABLE=1
[[ -x "$CLANG_DIR/bin/clang" && -s "$KOUT/Module.symvers" && -s "$KOUT/.config" && -s "$KOUT/arch/arm64/boot/Image" ]]
TASK_WORK=$(mktemp -d /tmp/wifi-mosey-ci.XXXXXX)
tar -xzf "$PACKAGE/driver-source.tar.gz" -C "$TASK_WORK"
python3 "$PACKAGE/prepare-cfg80211.py" "$KERNEL/include/net/cfg80211.h" "$PACKAGE/cfg80211-patches" "$TASK_WORK/generated-compat"
# Ensure the reviewed normalization and patches reproduce the saved stock overlay.
cmp "$TASK_WORK/generated-compat/include/net/cfg80211.h" "$TASK_WORK/vendor-compat/include/net/cfg80211.h"
python3 - "$KOUT/Module.symvers" "$PACKAGE/stock-vendor-exports.symvers" "$TASK_WORK/stock-vendor-exports.symvers" <<'PY_SYMVERS'
import sys
from pathlib import Path
kernel={row.split()[1]:row.split()[0] for row in Path(sys.argv[1]).read_text().splitlines() if len(row.split()) >= 2}
rows=[]
for row in Path(sys.argv[2]).read_text().splitlines():
    fields=row.split()
    if len(fields)<2: raise SystemExit('Malformed stock vendor symvers')
    crc,name=fields[:2]
    if name in kernel:
        if int(crc,16)!=int(kernel[name],16): raise SystemExit(f'Conflicting kernel/vendor CRC for {name}')
    else: rows.append(row)
Path(sys.argv[3]).write_text('\n'.join(rows)+'\n')
PY_SYMVERS
CLANG_RESOURCE=$(clang -print-resource-dir)/include
checked_make() {
  local log
  log=$(mktemp /tmp/wifi-mosey-modpost.XXXXXX)
  make "$@" 2>&1 | tee "$log"
  if grep -E 'WARNING: modpost:|ERROR: modpost:|Symbol version dump.*missing' "$log"; then
    echo "Module symbol validation failed; see $log" >&2
    return 1
  fi
}
COMMON=( -C "$KERNEL" O="$KOUT" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 "NOSTDINC_FLAGS=-I$TASK_WORK/vendor-compat/include -nostdinc -isystem $CLANG_RESOURCE" )
checked_make -j"${BUILD_JOBS:-4}" "${COMMON[@]}" M="$TASK_WORK/provider" KCFLAGS="-I$TASK_WORK/wonder-samsung-api/wlan/wonder/include" modules
checked_make -j"${BUILD_JOBS:-4}" "${COMMON[@]}" M="$TASK_WORK/wonder-samsung-api/wlan/wonder" EXTRA_CFLAGS="-I$TASK_WORK/wonder-samsung-api/wlan/wonder/include -DWONDER_MAC80211_STA_LEGACY -DCONFIG_NL80211_TESTMODE=1" KBUILD_EXTRA_SYMBOLS="$TASK_WORK/stock-vendor-exports.symvers" modules
checked_make -j"${BUILD_JOBS:-4}" "${COMMON[@]}" M="$TASK_WORK/wlan-driver/qcacld-3.0" WLAN_ROOT="$TASK_WORK/wlan-driver/qcacld-3.0" WLAN_COMMON_ROOT=cmn WLAN_COMMON_INC="$TASK_WORK/wlan-driver/qca-wifi-host-cmn" WLAN_FW_API="$TASK_WORK/wlan-driver/fw-api" WLAN_PLATFORM_INC="$TASK_WORK/wlan-driver/platform/inc" KBUILD_EXTRA_SYMBOLS="$TASK_WORK/stock-vendor-exports.symvers $TASK_WORK/provider/Module.symvers" MODNAME=qca_cld3_kiwi_v2 CHIP_NAME=kiwi_v2 WLAN_CTRL_NAME=wlan CONFIG_QCA_CLD_WLAN=m CONFIG_QCA_CLD_WLAN_PROFILE=anorak_gki_kiwi-v2 'WLAN_CFG_OVERRIDE=CONFIG_DRIVER_PASSTHRU_MODE=y CONFIG_BUILD_TAG=n CONFIG_IPA_OFFLOAD=n CONFIG_CNSS_OUT_OF_TREE=y CONFIG_S23U_LEGACY_CNSS=y CONFIG_WLAN_SYNC_TSF_PLUS=n CONFIG_WLAN_SYNC_TSF_PLUS_NOIRQ=n' KCFLAGS="-I$TASK_WORK/wonder-samsung-api/wlan/wonder/include -DCFG80211_SINGLE_NETDEV_MULTI_LINK_SUPPORT -DCFG80211_11BE_BASIC -DCONFIG_NL80211_TESTMODE=1 -DCFG80211_SAE_AUTH_TA_ADDR_SUPPORT" modules
mkdir -p "$DEST"
cp "$TASK_WORK/provider/s23u_wonder_provider.ko" "$TASK_WORK/wonder-samsung-api/wlan/wonder/wonder.ko" "$TASK_WORK/wlan-driver/qcacld-3.0/qca_cld3_kiwi_v2.ko" "$DEST/"
llvm-strip --strip-debug "$DEST"/*.ko
RELEASE=$(cat "$KOUT/include/config/kernel.release")
for module in "$DEST"/*.ko; do
  [[ "$(modinfo -F vermagic "$module" | cut -d ' ' -f1)" == "$RELEASE" ]] || { echo "Unexpected module vermagic: $module" >&2; exit 1; }
  if llvm-nm --undefined-only "$module" | awk '{print $NF}' | grep -Fx cfg80211_notify_new_peer_candidate >/dev/null; then
    echo "Unreviewed stock cfg80211 peer-candidate import: $module" >&2
    exit 1
  fi
done
python3 - "$KOUT/arch/arm64/boot/Image" "$DEST" "$RELEASE" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
image=Path(sys.argv[1]); dest=Path(sys.argv[2]); names=['qca_cld3_kiwi_v2.ko','s23u_wonder_provider.ko','wonder.ko']
hashfile=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest={'kernel_image_sha256':hashfile(image),'kernel_release':sys.argv[3], 'modules':{n:hashfile(dest/n) for n in names},'compiler':subprocess.check_output(['clang','--version'],text=True).splitlines()[0]}
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
