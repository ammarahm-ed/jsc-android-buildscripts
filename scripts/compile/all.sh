#!/bin/bash -e

SCRIPT_DIR=$(cd `dirname $0`; pwd)

compile_arch() {
  echo -e '\033]2;'"compiling icu for $JSC_ARCH $FLAVOR"'\007'
  printf "\n\n\n\t\t=================== compiling icu for $JSC_ARCH $FLAVOR ===================\n\n\n"
  $SCRIPT_DIR/icu.sh

  echo -e '\033]2;'"compiling jsc for $JSC_ARCH $FLAVOR"'\007'
  printf "\n\n\n\t\t=================== compiling jsc for $JSC_ARCH $FLAVOR ===================\n\n\n"
  $SCRIPT_DIR/jsc.sh

  echo "-= Finished compiling for $JSC_ARCH $FLAVOR =-"
}

compile() {
  # 32-bit ABIs: only when INCLUDE_32_BIT_ABIS=1. Override the list with
  # JSC_ARCHS_32 (e.g. "arm") to build a single 32-bit ABI.
  local archs32=""
  if [[ "${INCLUDE_32_BIT_ABIS:-0}" == "1" ]]; then
    archs32="${JSC_ARCHS_32-arm x86}"
  fi
  for arch in $archs32
  do
    export ANDROID_API=$ANDROID_API_FOR_ABI_32
    export JSC_ARCH=$arch
    compile_arch
  done

  # 64-bit ABIs. Override with JSC_ARCHS_64 (e.g. "arm64" for a single arch, or
  # "" to skip all 64-bit ABIs). Uses ${VAR-default} so an explicit empty value
  # means "none" while unset means the full default list.
  for arch in ${JSC_ARCHS_64-arm64 x86_64}
  do
    export ANDROID_API=$ANDROID_API_FOR_ABI_64
    export JSC_ARCH=$arch
    compile_arch
  done
}

if ${I18N}
then
  export FLAVOR=intl
  export ENABLE_INTL=1
  compile
else
  export FLAVOR=no-intl
  export ENABLE_INTL=0
  compile
fi
