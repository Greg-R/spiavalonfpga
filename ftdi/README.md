Instructions for automating FTDI USB-SPI Device Operations
----------------------------------------------------------

These instructions were developed using Ubuntu 18.04.
Other distributions may have different requirements.
This describes the problem with the ftdi_sio and usbserial
kernel modules which interfere with the MPSSE library functions.
These two kernel modules must be removed for the MPSSE to function.

There are two separate problems:
1.  One is dealing with the kernel modules at boot.
2.  Dealing with the kernel modules after
boot, when the USB plug is unpluggled and plugged back in.

Problem 1
---------

There are probably many ways to solve the boot problem.
This method uses a simple systemd service.

Copy the file rmmod_ftdi.service to this directory:

/etc/systemd/system/multi-user.target.wants

Now enable the service with this command:

sudo systemctl enable rmmod_ftdi.service

That is all that is required.  Now on the next boot, the
interferring kernel modules will be removed.

Problem 2
---------

If there is an error in the Julia program, the FTDI device
will not be closed and it will hang up.  The easiest way
to fix this is to unplug-plug the device.

However, the kernel modules will reappear.  Removing them
is easily automated using udev.

Copy the files 11-ftdi.rules and rm_ftdi_modules.sh
to the directory:

/etc/udev/rules.d

The shell script rm_ftdi_modules.sh will be run automatically
whenever the FTDI USB device is unplugged-plugged.
