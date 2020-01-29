# nilrt-net-boot: NI Linux RT Network Boot Tools

Network booting is the process of booting a computer system from a
network rather than local disk/flash media. The system's kernel and file
systems are retrieved over the network by firmware/BIOS instead of
accessing those files from local storage. In many cases, storage devices
can be completely removed from these systems to reduce cost. These
schemes are typically employed to centralize software and system
configuration to reduce maintenance overhead.

Preboot Execution Environment (PXE) is a common protocol to implement
network boot. It's supported on some NI controllers like PXIe-8840.
The tutorial below demonstrates PXE network booting an NI Linux RT OS
with user installed software (E.g. LabVIEW RT built app) on PXI.

Written by Haris Okanovic <haris.okanovic@ni.com> to demonstrate
network boot capabilities of NI Linux RT. Use at your own risk.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


## Create ramdisk image

1. Format, install software, and otherwise configure a real (hardware)
   controller using MAX, SD, LabVIEW, and/or other tools. This will
   serve as a template system to take an image.

2. Reboot to safemode

3. Copy the enclosed nilrt-make-netboot-image.sh to admin's home
   directory via ssh/sftp.

4. Run `nilrt-make-netboot-image.sh -i /mnt/userfs -o /media/my_usb_storage/img.d`
   as admin to take an image to /media/my_usb_storage/nilrt-image.dir .

5. Copy `img.d` into the enclosed `tftpboot`, which contains a few other
   files needed for PXE boot.


## TFTP Root Directory Layout

Once `img.d` is copied, the `tftpboot` dir should look like this:

```
tftpboot/
    img.d/
        bzImage - Linux kernel image
        init - gzipped cpio ramdisk of runmode filesystem
        SHA256SUM - checksums of aforementioned files
    pxelinux.cfg/
        default - PXE configuration file tuned for NI Linux RT
    pxelinux.0 - x86_64 Syslinux PXE boot loader
    ldlinux.c32 - x86_64 Syslinux PXE boot loader
```

NOTE: You can compile your own Syslinux PXE boot loader if desired.

Syslinux PXE Documentation: https://wiki.syslinux.org/wiki/index.php?title=PXELINUX

Syslinux Source: https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/


## PXE Image Hosting Example

NOTE: This simple example uses dnsmasq to provide DHCP and TFTP services
on an isolated network, directly connected to hardware we're booting.
This configuration is intended only to demonstrate PXE booting
capabilities in the simplest environment possible. Please take care when
adapting this example for your network. Hosting a second DHCP service
may create problems for other users/devices on your network!

1. Connect a PXE capable NI controller (E.g. PXIe-8840) to an unused
   Ethernet adapter on your desktop. We'll call that adapter "demoEth".
   You can connect a USB Ethernet adapter if you don't have a second
   one to work with.

2. Run `sudo ifconfig demoEth 192.168.92.1/24` to give demoEth a static
   address on the new network. You can change the `192.168.92.X` subnet
   if it's already in use. Be sure to update dnsmasq.conf accordingly.

3. Run `dnsmasq --no-daemon --conf-file=dnsmasq.conf --tftp-root="$PWD/tftpboot" --interface=demoEth`
   to launch DHCP and TFTP services.

4. Boot the NI controller to BIOS by repeatedly pressing DEL after
   powering on.

5. Go to the "Boot" tab.
   Enable the "PXE Network Boot" option.
   Disable all "Boot Option ##"'s, except the network adapter.

6. Save and reboot in BIOS: Go to "Save & Exit" tab then click on "Save
   Changes and Reset" option.

7. You should see the PXE boot agent run, download several files via
   TFTP, and boot into NI Linux RT. It will retry indefinitely if
   DHCP and TFTP are not configured correctly and you did not specify
   a fallback boot device in BIOS.

