#!/bin/bash
set -euo pipefail

umask 0133

function error()
{
    echo "ERROR: $*"
    false
}

function warning()
{
    echo "WARNING: $*"
}

function status()
{
    echo "INFO: $*"
}

function print_help_and_exit () {
    cat <<ENDHELP

Usage: $0 -i /mnt/userfs -o /media/my_usb_storage/nilrt-image.dir [ -k /mnt/userfs/boot/runmode/bzImage ]
 Creates a PXE bootable image of NI Linux RT system, containing a kernel
 image and inital RAM disk (initrd) image of runmode filesystem.

Args:
 -i: Path to root filesystem of directory NI Linux RT runmode which
     are copied into the initrd image.
 -o: Output direcotry where image file will be stored. All existing
     files and dirs under this path will be erased and replaced with
     generated image. This must be an absolute path beginning with '/'.
 -k: (Optional) Path to kernel image. Defaults to /boot/runmode/bzImage
     under the sysroot. This must be an absolute path beginning with
     '/' if specified.

Written by Haris Okanovic <haris.okanovic@ni.com> to demonstrate
network boot capabilities of NI Linux RT. Use at your own risk.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

ENDHELP

if [ $# -gt 0 ]; then
    error "$*" || true
    echo ""
    false
else
    exit 0
fi
}

image_dir=""
sysroot_dir=""
kernel_img_file=""

while getopts "ho:i:k:" opt; do
    case "$opt" in
    h )  print_help_and_exit ;;
    o )  image_dir="$OPTARG" ;;
    i )  sysroot_dir="$OPTARG" ;;
    k )  kernel_img_file="$OPTARG" ;;
    esac
done
shift $(($OPTIND - 1))


[ -n "$image_dir" ] || print_help_and_exit "Must specify output image path with -o"
[ "${image_dir:0:1}" == "/" ] || print_help_and_exit "Output image path (-o) must be absolute, start with \"/\""
[ ! -e "$image_dir" ] || warning "$image_dir already exists, overwriting"

[ -n "$sysroot_dir" ] || print_help_and_exit "Must specify sysroot directory with -i"


if [ -n "$kernel_img_file" ]; then
    [ "${kernel_img_file:0:1}" == "/" ] || print_help_and_exit "Kernel image path (-k) must be absolute, start with \"/\""
    [ -f "$kernel_img_file" ] || error "$kernel_img_file does not exist"
else
    if [ -e "$sysroot_dir/boot/runmode/bzImage" ]; then
        kernel_img_file="$sysroot_dir/boot/runmode/bzImage"
    elif [ -e "/boot/runmode/bzImage" ]; then
        warning "No kernel image found at \"$sysroot_dir/boot/runmode/bzImage\", defaulting to \"/boot/runmode/bzImage\""
        kernel_img_file="/boot/runmode/bzImage"
    else
        error "No kernel image found at \"$sysroot_dir/boot/runmode/bzImage\" nor \"/boot/runmode/bzImage\", must specify with -k"
    fi
fi


readonly TEMP_DIR=$(mktemp -d "/tmp/netboot-temp-XXXXXXX")
chmod 0700 "$TEMP_DIR"

function cleanup()
{
    local exitCode="$?"
    set +e

    status "Cleanup TEMP_DIR=$TEMP_DIR"
    rm -Rf "$TEMP_DIR"

    exit "$exitCode"
}

trap cleanup EXIT


status "Clearing $image_dir"
rm -Rf "$image_dir"
[ ! -e "$image_dir" ] || error "Failed to clear image_dir=$image_dir"
mkdir -m 0755 "$image_dir"


status "Packing up $sysroot_dir into init"
cd "$sysroot_dir" >/dev/null
(
    find "." -xdev \
           -not -path "./boot/*" \
        -a -not -path "./etc/natinst/share/*" \
        -a -not -path "./init" \
        -a -not -path "./etc/fstab" \
        -a -not -path "./etc/hostname" \
        -a -not -path "./etc/init.d/niopendisks" \
        -a -not -path "./etc/init.d/niclosedisks" \
        -print

    find "./etc/natinst/share" -xdev \
           -not -path "./etc/natinst/share/ni-rt.ini" \
        -a -not -path "./etc/natinst/share/random-seed" \
        -a -not -path "./etc/natinst/share/ssh/*" \
        -a -not -path "./etc/natinst/share/certstore/open_csrs/*" \
        -a -not -path "./etc/natinst/share/certstore/server_certs/*" \
        -a -not -path "./etc/natinst/share/certstore/temp/*" \
        -a -not -path "./etc/natinst/share/certstore/certstore/wireless/client/*" \
        -a -not -path "./etc/natinst/share/certstore/certstore/wireless/pac/*" \
        -print

) | cpio --quiet -H newc -o | gzip -9 -n > "$image_dir/init"
cd - >/dev/null


status "Create override dir"
readonly OVR_DIR="$TEMP_DIR/override"
mkdir -m 0755 "$OVR_DIR"

ln -sf "sbin/init" "$OVR_DIR/init"

mkdir -m 0755 "$OVR_DIR/etc"
sed "/^LABEL=/d; /^\/dev\//d" "$sysroot_dir/etc/fstab" > "$OVR_DIR/etc/fstab"
chmod 0644 "$OVR_DIR/etc/fstab"

mkdir -m 0755 "$OVR_DIR/etc/natinst"
mkdir -m 0755 "$OVR_DIR/etc/natinst/share"
sed "/^PrimaryMAC=/d; /^host_name=/d" "$sysroot_dir/etc/natinst/share/ni-rt.ini" > "$OVR_DIR/etc/natinst/share/ni-rt.ini"


status "Appending $OVR_DIR to init"
cd "$OVR_DIR" >/dev/null
find "." -xdev -print | cpio --quiet -H newc -o | gzip -9 -n >> "$image_dir/init"
cd - >/dev/null


status "Copying $kernel_img_file"
cp "$kernel_img_file" "$image_dir/"


cd "$image_dir" >/dev/null
status "Checksum files"
sha256sum * > SHA256SUM
status "Successfully created image at $image_dir"
ls -alFh
cd - >/dev/null


status "DONE"

