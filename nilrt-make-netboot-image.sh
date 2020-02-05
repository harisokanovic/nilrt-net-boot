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
 Creates a PXE bootable image of an NI Linux RT system. This image is a
 direcotry containing the runmode kernel and an inital RAM disk (initrd)
 image of it's runmode filesystem, with identity information (like
 hostname, network config, ssh keys, certificates, etc) stripped out.

Args:
 -i: Path to root filesystem of directory NI Linux RT runmode which
     are copied into the initrd image.
 -o: Output direcotry where image file will be stored. All existing
     files and dirs under this path will be erased and replaced with
     generated image. This must be an absolute path beginning with '/'.
 -k: (Optional) Path to kernel image. Defaults to /boot/runmode/bzImage
     under the sysroot. This must be an absolute path beginning with
     '/' if specified.
 -b  (Optional) Files and directories to blacklist - exclude from image.
     You can pass this parameter multiple times. '*' is wildcard, which
     matches anything. E.g. Passing '-b foo.txt -b bar.dir -b gaz.dir/*'
     excludes the file /foo.txt, /bar.dir but NOT it's contents, and
     /gaz.dir's contents but NOT /gaz.dir itself. Paths are relative to
     the specified root filesystem (-i option).

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
blacklist_paths=()

while getopts "ho:i:k:b:" opt; do
    case "$opt" in
    h )  print_help_and_exit ;;
    o )  image_dir="$OPTARG" ;;
    i )  sysroot_dir="$OPTARG" ;;
    k )  kernel_img_file="$OPTARG" ;;
    b )  blacklist_paths+=( "$OPTARG" )
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


find_blacklist_exclude=""
for i in ${!blacklist_paths[@]}; do
    path="${blacklist_paths[i]}"
    [ "${path:0:1}" != "/" ] || print_help_and_exit "Blacklist path=$path must be relative to root filesystem, must not start with /"

    # Relative to sysroot_dir
    path="./$path"

    find_blacklist_exclude="$find_blacklist_exclude -a -not -path $path"
done


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
        $find_blacklist_exclude \
        -print

    if [  -e "./etc/natinst/share"  ]; then
        find "./etc/natinst/share" -xdev \
               -not -path "./etc/natinst/share/ni-rt.ini" \
            -a -not -path "./etc/natinst/share/random-seed" \
            -a -not -path "./etc/natinst/share/ssh/*" \
            -a -not -path "./etc/natinst/share/certstore/open_csrs/*" \
            -a -not -path "./etc/natinst/share/certstore/server_certs/*" \
            -a -not -path "./etc/natinst/share/certstore/temp/*" \
            -a -not -path "./etc/natinst/share/certstore/certstore/wireless/client/*" \
            -a -not -path "./etc/natinst/share/certstore/certstore/wireless/pac/*" \
            $find_blacklist_exclude \
            -print
    fi

) | cpio --quiet -H newc -o | gzip -9 -n > "$image_dir/init"
cd - >/dev/null


status "Create override dir"
readonly OVR_DIR="$TEMP_DIR/override"
mkdir -m 0755 "$OVR_DIR"

ln -sf "sbin/init" "$OVR_DIR/init"

if [ -e "$sysroot_dir/etc/fstab" ]; then
    mkdir -m 0755 "$OVR_DIR/etc"
    sed "/^LABEL=/d; /^\/dev\//d" "$sysroot_dir/etc/fstab" > "$OVR_DIR/etc/fstab"
    chmod 0644 "$OVR_DIR/etc/fstab"
fi

if [ -e "$sysroot_dir/etc/natinst/share/ni-rt.ini" ]; then
    mkdir -m 0755 "$OVR_DIR/etc/natinst"
    mkdir -m 0755 "$OVR_DIR/etc/natinst/share"
    sed "/^PrimaryMAC=/d; /^host_name=/d" "$sysroot_dir/etc/natinst/share/ni-rt.ini" > "$OVR_DIR/etc/natinst/share/ni-rt.ini"
fi


status "Appending $OVR_DIR to init"
cd "$OVR_DIR" >/dev/null
find "." -xdev $find_blacklist_exclude -print | cpio --quiet -H newc -o | gzip -9 -n >> "$image_dir/init"
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

