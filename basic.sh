#!/bin/bash

OSK="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc"
VMDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
OVMF=$VMDIR/firmware
#export QEMU_AUDIO_DRV=pa
#QEMU_AUDIO_DRV=pa

echo $VMDIR
if [[ "$EUID" != 0 && $1 == "vfio" ]]; then
    echo "Please run as root"
    exit 1
fi

if [[ $1 == "vfio" ]]; then
    modprobe vfio-pci
    if [[ $2 == '2' ]]; then
        host="00:14.0"
        BIND_PID1="8086 8c31"
    elif [[ $2 == '3' ]]; then
        host="03:00.3"
        BIND_PID1="1022 1639"
    else
        host="00:14.0"
        BIND_PID1="8086 9d2f"
        BIND_PID2="8086 9d31"
        BIND_BDF2="0000:00:14.2"
    fi
    BIND_BDF1="0000:$host"
    echo "$BIND_PID1" > /sys/bus/pci/drivers/vfio-pci/new_id
    echo "$BIND_BDF1" > /sys/bus/pci/devices/$BIND_BDF1/driver/unbind
    echo "$BIND_BDF1" > /sys/bus/pci/drivers/vfio-pci/bind
    echo "$BIND_PID1" > /sys/bus/pci/drivers/vfio-pci/remove_id
    if [[ -n $BIND_BDF2 && -n $BIND_PID2 ]]; then
        echo "$BIND_PID2" > /sys/bus/pci/drivers/vfio-pci/new_id
        echo "$BIND_BDF2" > /sys/bus/pci/devices/$BIND_BDF2/driver/unbind
        echo "$BIND_BDF2" > /sys/bus/pci/drivers/vfio-pci/bind
        echo "$BIND_PID2" > /sys/bus/pci/drivers/vfio-pci/remove_id
    fi
    extra="-device vfio-pci,host=$host"
elif [[ $1 == "install" ]]; then
    [[ ! -e vol.qcow2 ]] && qemu-img create -f qcow2 vol.qcow2 64G
    extra="-drive id=InstallMedia,format=raw,if=none,file=$VMDIR/BaseSystem.img \
           -device ide-hd,bus=sata.3,drive=InstallMedia"
elif [[ $1 == "custom" ]]; then
    extra="$2"
fi

if [[ ! -e $VMDIR/firmware/OVMF_VARS-1024x768.fd ]]; then
    curl -L https://github.com/foxlet/macOS-Simple-KVM/raw/master/firmware/OVMF_VARS-1024x768.fd -o firmware/OVMF_VARS-1024x768.fd
fi

qemu-system-x86_64 \
    -enable-kvm \
    -m 2G \
    -machine q35,accel=kvm \
    -smp 4,cores=2 \
    -cpu Penryn,vendor=GenuineIntel,kvm=on,+sse3,+sse4.2,+aes,+xsave,+avx,+xsaveopt,+xsavec,+xgetbv1,+avx2,+bmi2,+smep,+bmi1,+fma,+movbe,+invtsc \
    -device isa-applesmc,osk="$OSK" \
    -smbios type=2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF/OVMF_CODE.fd" \
    -drive if=pflash,format=raw,file="$OVMF/OVMF_VARS-1024x768.fd" \
    -vga qxl \
    -device ich9-intel-hda -device hda-output \
    -usb -device usb-kbd -device usb-mouse \
    -netdev user,id=net0,hostfwd=tcp::5555-:22 \
    -device e1000-82545em,netdev=net0,id=net0,mac=52:54:00:c9:18:27 \
    -device ich9-ahci,id=sata \
    -drive id=ESP,if=none,format=qcow2,file=$VMDIR/OpenCore-nopicker.qcow2 \
    -device ide-hd,bus=sata.2,drive=ESP \
    -drive id=SystemDisk,if=none,file=$VMDIR/vol.qcow2 \
    -device ide-hd,bus=sata.4,drive=SystemDisk \
    $extra

if [[ $1 == "vfio" ]]; then
    echo "$BIND_BDF1" > /sys/bus/pci/drivers/vfio-pci/unbind
    echo "$BIND_BDF1" > /sys/bus/pci/drivers/xhci_hcd/bind
    [[ -n $BIND_BDF2 ]] && echo "$BIND_BDF2" > /sys/bus/pci/drivers/vfio-pci/unbind
fi
