#!/bin/bash

# derived from code from:
# https://pastebin.com/VtAusEmf (author unknown)
# and 
# David Lechner <david@lechnology.com>  https://github.com/ev3dev/ev3-systemd/blob/ev3dev-buster/scripts/ev3-usb.sh

# Copyright (C) 2015,2017 David Lechner <david@lechnology.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.

# 2020 changes by rundekugel @github:
# - more easy to use with default params
# - changes to use with other embedded systems

# command line parameters

command="up" # "up" or "down"

vid="0xffff" # set your vendor id 
pid="0xffff" # set your product id 
devversion="0x0001" # this should be incremented any time there are breaking changes
                # to this script so that the host OS sees it as a new device and
                # re-enumerates everything rather than relying on cached values
mfg="my name" # adjust
prod="product name" # adjust
serial="t00000002" # adjust
smac=""
udc_device=""
verbose=1
m1d=""
m1h=""
m2d=""
m2h=""
mac=""

#while getopts 'v:p:P:M:m:c:u:s:d:1:2:3:4h?V' c
# getopts is not enough, so parse manually
for arg in "$@"; do
  shift
  case $arg in
    up|down) command=$arg ;;
    -vid) vid=$1 ;;  
    -pid) pid=$1 ;;  
    -mstr) mfg=$1 ;;
    -pstr) prod=$1 ;;
    -ser) serial=$1 ;;
    -mac) smac=$1; mac=1 ;;
    -dver) devversion=$1 ;;
    -udc) udc_device=$1 ;;
    -m1d) m1d=$1; mac=1 ;;
    -m1h) m1h=$1; mac=1 ;;
    -m2d) m2d=$1; mac=1 ;;
    -m2h) m2h=$1; mac=1 ;;
    -h|--help|"-?"|"?") command="h" ;;
    -v) verbose=$1 ;;
  esac  
done

if [ "$command" == "" ]; then command=h; fi
if [ -z "$verbose" ]; then verbose=1 ;fi

if [ "$command" != "h" ]; then
  if [ "$udc_device" == "" ]; then
   udc_device=$(ls /sys/class/udc)
  fi
  if [ "$verbose" -gt "0" ];then echo udc: $udc_device; fi
fi

if [ "$verbose" -gt "2" ];then
  echo debug: params: $vid,$pid,$mfg,$prod,$serial,$smac,$devversion,$udc_device,Verbose=$verbose
  echo mac: $m1d,$m1h,$m2d,$m2h
fi

g="/sys/kernel/config/usb_gadget/usbnet"

un_usb_up() {
    modprobe libcomposite
    mount -t configfs none /sys/kernel/config
    set -e
    usb_ver="0x0200" # USB 2.0
    dev_class="2" # Communications 
    attr="0xC0" # Self powered
    pwr="0xfe" # 
    cfg1="CDC"
    cfg2="RNDIS"
    ms_vendor_code="0xcd" # Microsoft
    ms_qw_sign="MSFT100" # also Microsoft (if you couldn't tell)
    ms_compat_id="RNDIS" # matches Windows RNDIS Drivers
    ms_subcompat_id="5162001" # matches Windows RNDIS 6.0 Driver

    if [ -d ${g} ]; then
        if [ "$(cat ${g}/UDC)" != "" ]; then
            if [ "$verbose" -gt "0" ];then echo "Gadget is already up."; fi
            exit 1
        fi
        if [ "$verbose" -gt "0" ];then echo "Cleaning up old directory..."; fi
        un_usb_down
    fi
    if [ "$verbose" -gt "0" ];then echo "Setting up gadget..."; fi
   
    ms_vendor_code="0xcd" # Microsoft
    ms_qw_sign="MSFT100" # also Microsoft (if you couldn't tell)
    ms_compat_id="RNDIS" # matches Windows RNDIS Drivers
    ms_subcompat_id="5162001" # matches Windows RNDIS 6.0 Driver
    
    # Create a new gadget

    mkdir ${g}
    echo "${usb_ver}" > ${g}/bcdUSB
    echo "${dev_class}" > ${g}/bDeviceClass
    echo "${vid}" > ${g}/idVendor
    echo "${pid}" > ${g}/idProduct
    echo "${devversion}" > ${g}/bcdDevice
    mkdir ${g}/strings/0x409
    echo "${mfg}" > ${g}/strings/0x409/manufacturer
    echo "${prod}" > ${g}/strings/0x409/product
    echo "${serial}" > ${g}/strings/0x409/serialnumber

    # Create 2 configurations. The first will be CDC. The second will be RNDIS.
    # Thanks to os_desc, Windows should use the second configuration.

    # config 1 is for CDC

    mkdir ${g}/configs/c.1
    echo "${attr}" > ${g}/configs/c.1/bmAttributes
    echo "${pwr}" > ${g}/configs/c.1/MaxPower
    mkdir ${g}/configs/c.1/strings/0x409
    echo "${cfg1}" > ${g}/configs/c.1/strings/0x409/configuration

    # Create the CDC function

    mkdir ${g}/functions/ecm.usb0
   
   # config 2 is for RNDIS

    mkdir ${g}/configs/c.2
    echo "${attr}" > ${g}/configs/c.2/bmAttributes
    echo "${pwr}" > ${g}/configs/c.2/MaxPower
    mkdir ${g}/configs/c.2/strings/0x409
    echo "${cfg2}" > ${g}/configs/c.2/strings/0x409/configuration

    # On Windows 7 and later, the RNDIS 5.1 driver would be used by default,
    # but it does not work very well. The RNDIS 6.0 driver works better. In
    # order to get this driver to load automatically, we have to use a
    # Microsoft-specific extension of USB.

    echo "1" > ${g}/os_desc/use
    echo "${ms_vendor_code}" > ${g}/os_desc/b_vendor_code
    echo "${ms_qw_sign}" > ${g}/os_desc/qw_sign

    # Create the RNDIS function, including the Microsoft-specific bits

    mkdir ${g}/functions/rndis.usb0
    echo "${ms_compat_id}" > ${g}/functions/rndis.usb0/os_desc/interface.rndis/compatible_id
    echo "${ms_subcompat_id}" > ${g}/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

    if [ -n "$mac" ]; then
      if [ -n "$smac" ]; then
        # Change the first number for each MAC address - the second digit of 2 indicates
        # that these are "locally assigned (b2=1), unicast (b1=0)" addresses. This is
        # so that they don't conflict with any existing vendors. Care should be taken
        # not to change these two bits.
        dev_mac1="02$(echo ${smac} | cut -b 3-)"
        host_mac1="12$(echo ${smac} | cut -b 3-)"
        dev_mac2="22$(echo ${smac} | cut -b 3-)"
        host_mac2="32$(echo ${smac} | cut -b 3-)"
      fi
      if [ -n "$m1d" ]; then dev_mac1=$m1d ; fi
      if [ -n "$m1h" ]; then host_mac1=$m1h ; fi
      if [ -n "$m2d" ]; then dev_mac2=$m2d ; fi
      if [ -n "$m1h" ]; then host_mac2=$m2h ; fi
      
      if [ -n "$dev_mac1"  ]; then echo "${dev_mac1}"  > ${g}/functions/ecm.usb0/dev_addr ; fi
      if [ -n "$host_mac1" ]; then echo "${host_mac1}" > ${g}/functions/ecm.usb0/host_addr ; fi
      if [ -n "$dev_mac2"  ]; then echo "${dev_mac2}"  > ${g}/functions/rndis.usb0/dev_addr ; fi
      if [ -n "$host_mac2" ]; then echo "${host_mac2}" > ${g}/functions/rndis.usb0/host_addr ; fi  
    fi # else gadgetfs chooses random addresses
    
    # Link everything up and bind the USB device
    ln -s ${g}/functions/ecm.usb0 ${g}/configs/c.1
    ln -s ${g}/functions/rndis.usb0 ${g}/configs/c.2
    ln -s ${g}/configs/c.2 ${g}/os_desc
    echo "${udc_device}" > ${g}/UDC
    
    if [ -n "$verbose" ]; then echo "Done."; fi
}

un_usb_down() {
    if [ ! -d ${g} ]; then
        if [ "$verbose" -gt "0" ];then echo "Gadget is already down."; fi
        exit 1
    fi
    if [ "$verbose" -gt "0" ];then echo "Taking down gadget..."; fi

    # Have to unlink and remove directories in reverse order.
    # Checks allow to finish takedown after error.

    if [ "$(cat ${g}/UDC)" != "" ]; then
        echo "" > ${g}/UDC
    fi
    rm -f ${g}/os_desc/c.2
    rm -f ${g}/configs/c.2/rndis.usb0
    rm -f ${g}/configs/c.1/ecm.usb0
    [ -d ${g}/functions/ecm.usb0 ] && rmdir ${g}/functions/ecm.usb0
    [ -d ${g}/functions/rndis.usb0 ] && rmdir ${g}/functions/rndis.usb0
    [ -d ${g}/configs/c.2/strings/0x409 ] && rmdir ${g}/configs/c.2/strings/0x409
    [ -d ${g}/configs/c.2 ] && rmdir ${g}/configs/c.2
    [ -d ${g}/configs/c.1/strings/0x409 ] && rmdir ${g}/configs/c.1/strings/0x409
    [ -d ${g}/configs/c.1 ] && rmdir ${g}/configs/c.1
    [ -d ${g}/strings/0x409 ] && rmdir ${g}/strings/0x409
    rmdir ${g}

    if [ -n "$verbose" ]; then echo "Done."; fi
}

case ${command} in
up)
    un_usb_up
    ;;
down)
    un_usb_down
    ;;
*)
  echo "Create USB Gadget device dual CDC/ECM and rndis V0.1.1 for MAC, Linux and Windows"
  echo "Original copyright (C) 2015,2017 David Lechner <david@lechnology.com>"
  echo "Modified 2020 by rundekugel @github"
  echo " "
  echo "Usage: $0 up|down [options]"
  echo " options:"
  echo " --------"
  echo " up     activate"
  echo " down   deactivate"
  echo " -vid   vid "
  echo " -pid   pid "
  echo " -mstr  Manufacturer String"
  echo " -pstr  Product name string"
  echo " -ser   Serial Number"
  echo " -mac   Mac Addresses will be derived from this parameter"
  echo " -dver  USB Device Version"
  echo " -udc   udc_device. change only, if you have multiple USB-OTG interfaces."
  echo " -v     set verbose level 0..3"
  echo " -h|--help|-?|?   info"
  echo " -m1d , -m1h, -m2d, -m2h  : mac id for local ecm, mac id for host ecm, mac id for local rndis, mac id for host rndis. This overwrites -mac"
  exit 1
    ;;
esac

#--- eof ---
