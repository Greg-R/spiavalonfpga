SPI AVALON FPGA
---------------
---------------

An FPGA project based on the Terasic DE10-Lite MAX10 Development board.
The project uses an FTDI FT232H USB to SPI device to create a bi-directional
interface to the FPGA from a desktop computer.

Everything was developed using a desktop computer running Ubuntu 18.04.

doc/spi_avalon_fpga directory includes the PDF documentation file.
src has the Julia code.
fpga has a Quartus archive file for the MAX10 FPGA.
ftdi has details on automating kernel module removal.

This project was based on an excellent collection of projects
using the DE10-Lite:

https://github.com/hildebrandmw/de10lite-hdl
