# Set architecture (default: x86)
export ARCH=x86

# Toolchain and QEMU defaults for x86
PREFIX = i686-elf-
QEMU = qemu-system-i386
QEMU_ARCH_FLAG = -M q35

# Override toolchain and QEMU for RISC-V
ifeq ($(ARCH),riscv)
PREFIX = riscv32-elf-
QEMU = qemu-system-riscv32
QEMU_ARCH_FLAG = -M virt
endif

# Export toolchain variables
export CC= $(PREFIX)gcc
export CFLAGS= -fno-strict-aliasing -O2 -Wall -Wextra -std=c17 -fno-omit-frame-pointer \
		-fno-stack-protector -gdwarf-5 -Werror-implicit-function-declaration
export CXX= $(PREFIX)g++
export CXXFLAGS= -fno-strict-aliasing -O2 -Wall -Wextra -std=c++20 -fno-omit-frame-pointer -fno-stack-protector \
				-gdwarf-5 -fno-sized-deallocation -fno-exceptions -fno-rtti -fno-use-cxa-atexit -Werror-implicit-function-declaration
export ASFLAGS = -gdwarf-5
export AS= $(PREFIX)as

# Add x86-specific assembler flag
ifeq ($(ARCH),x86)
ASFLAGS += -Wa,-divide
endif

export LD= $(PREFIX)ld
export OBJCOPY= $(PREFIX)objcopy
export AR = $(PREFIX)ar

# Set user space and module build targets for x86
ifeq ($(ARCH),x86)
USERSPACE_MODULE_TARGET = program module
endif

# Default target: build the disk image
all: panicos.img

# Run QEMU with the built image (normal mode)
qemu: panicos.img
	$(QEMU) -debugcon mon:stdio -kernel kernel/kernel -drive file=panicos.img,format=raw,if=virtio \
	-smp 2 -m 128M -net none -rtc base=localtime $(QEMU_ARCH_FLAG)

# Run QEMU in GDB debug mode (waits for GDB to attach)
qemu-gdb: panicos.img
	$(QEMU) -debugcon mon:stdio -kernel kernel/kernel -drive file=panicos.img,format=raw,if=virtio \
	-smp 2 -m 128M -s -S -net none -rtc base=localtime $(QEMU_ARCH_FLAG)

# Run QEMU with KVM acceleration (if available)
qemu-kvm: panicos.img
	$(QEMU) -debugcon mon:stdio -kernel kernel/kernel -drive file=panicos.img,format=raw,if=virtio \
	-smp 2 -m 128M -accel kvm -cpu host -net none -rtc base=localtime $(QEMU_ARCH_FLAG)

# Run QEMU with TCG (software emulation)
qemu-tcg: panicos.img
	$(QEMU) -debugcon mon:stdio -kernel kernel/kernel -drive file=panicos.img,format=raw,if=virtio \
	-smp 2 -m 128M -accel tcg -cpu host -net none -rtc base=localtime $(QEMU_ARCH_FLAG)

# Build the full disk image (panicos.img)
panicos.img: boot/mbr.bin kernel/kernel rootfs share $(USERSPACE_MODULE_TARGET)
	dd if=/dev/zero of=fs.img bs=1M count=63
	mkfs.vfat -F32 -s1 -nPanicOS fs.img
	mcopy -i fs.img -s rootfs/* ::
	dd if=/dev/zero of=panicos.img bs=1M count=64
	dd if=boot/mbr.bin of=panicos.img conv=notrunc
	dd if=fs.img of=panicos.img bs=1M conv=notrunc seek=1
	rm -f fs.img

# Build the MBR boot sector
boot/mbr.bin:
	$(MAKE) -C boot mbr.bin

# Build the kernel and copy it to the rootfs
kernel/kernel: rootfs
	$(MAKE) -C kernel kernel
	cp kernel/kernel rootfs/boot

# Build user programs
.PHONY: program
program: library rootfs
	$(MAKE) -C program

# Build libraries
.PHONY: library
library: rootfs
	$(MAKE) -C library

# Install shared files
.PHONY: share
share: rootfs
	$(MAKE) -C share install

# Build kernel modules
.PHONY: module
module: rootfs
	$(MAKE) -C module

# Create the root filesystem structure
.PHONY: rootfs
rootfs:
	mkdir -p rootfs/bin rootfs/lib rootfs/devel/include rootfs/devel/lib \
	rootfs/share rootfs/boot/module

# Create a distribution tarball
.PHONY: dist
dist: kernel/kernel rootfs share $(USERSPACE_MODULE_TARGET)
	tar -czf panicos.tar.gz rootfs/*

# Clean all build artifacts
.PHONY: clean
clean:
	$(MAKE) -C boot clean
	$(MAKE) -C kernel clean
	$(MAKE) -C library clean
	$(MAKE) -C program clean
	$(MAKE) -C module clean
	rm -rf panicos.img rootfs panicos.tar.gz
