Instructions for running Julia programs.
Install the Julia binary:
https://julialang.org/

This directory is the root directory of the Julia project.
cd into this directory.  Use the ] key to go into "Package Mode".
In package mode, type this command:

activate .

This puts you into a Julia "environment", which is similar in concept
to a Python environment.

If you are running this project for the first time, run these commands
while still in package mode:

add Images

add ImageMagick

add ProgressMeter

add Printf

The above commands make take a few minutes to complete.

To exit package mode, use the Backspace key.
You will now be at the Julia REPL.  Use this command:

using spiavalonfpga

to load the functions from the Julia module.

If the FPGA is powered and the FTDI USB-SPI is plugged into the
computer, you can "send" the animated GIF image to the FPGA with
this command:

send("waterfall.gif")

If it fails, it is mostly likely the FTDI device is not ready.
Assuming you are running Linux, run this command:

sudo rmmod ftdi_sio usbserial

This will remove these kernel modules which interfere with the operation
of the MPSSE driver.

You may have to unplug-plug the USB connector first.
This is a bit of a hassle, however, the process can be automated.
See the FTDI folder for details on how to set up.

