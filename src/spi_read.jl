#  SPI Read function.  This version returns at single byte at the address.
#  This will need to form an Avalon packet, just like the write function.

#module spi_read
#import SPIManager

#=
What is the data flow of the read and write functions?
This process is pretty strange, since Julia is calling C library functions.
Also there are functions to initialize and call the FTDI SPI device mixed in.
I will ignore the FTDI in this commentary.
The C code, which is derived from the Altera example code, is built into a
"shared library".  The library has functions which translate read and write
requests into SPI data.  It is a bit confusing, as there are "Avalon Packets",
physical Avalon transfers, and then the SPI data itself, which is what is
sent to the FTDI device.

The C library creates its own buffers (arrays) which contain the SPI data.
Julia can "wrap" these buffers with the "unsafe_wrap" function, which is the
mechanism for Julia to access the C library generated arrays.

Since the C buffer/array is "malloced", Julia needs to get the pointer.
This is done with the get_send_byte_buffer_pointer() function, which was added
to the Altera example code for this purpose.

Also needed is the size of the buffer.  This size is variable, as there are
substitutions made by the Altera code to make the physical Avalon transfer, due
to having to work around characters used for special purposes, for example
end of buffer marking.  This is some quite funky C code.

With the pointer and buffer size available, the "unsafe_wrap" function opens
the door for Julia to use the C buffer to write to the FTDI SPI device.

Writing is fairly straightforward, as the physical Avalon transfer is created,
and this buffer is transmitted by an FTDI SPI write.  So this requires and
address and data.

The read, however, is a little trickier.  The Avalon documentation is not clear
on this.  This should require an address, and if more than one byte is being
read, the length.

=#

export readbyte, printit, readavalon
#  Path to the shared library:  /mnt/ds216/embedded_design/FPGA/avalon_bus_stuff/data_to_avalon_packets_library/build/default/libavalonpacket.so.  Non-sequential read is 0x00, Sequential read is 0x04.
readavalon(addr, size, buff) = ccall((:transaction_channel_read, "/mnt/ds216/embedded_design/FPGA/avalon_bus_stuff/data_to_avalon_packets_library/build/default/libavalonpacket"), UInt32, (UInt32, UInt32, Ptr{UInt8}, UInt32), addr, size, buff, 0x04)
#  Note, the buff parameter is meaningless here.  It can be a dummy buffer, and it won't be useful.
#  In the original project, the SPI command would be used to populate this buffer.  Can't do that here, it is more of a multi-step process.
#packet_length() = ccall((:get_xmit_packet_length, "/mnt/ds216/embedded_design/FPGA/avalon_bus_stuff/data_to_avalon_packets_library/build/default/libavalonpacket"), UInt32,(),)

#  The function should return the retrieved data.
function readbyte(
            address
       )

    # Open the channel to the SPI device.
    SPIManager.SPI_GetNumChannels()
    SPIManager.SPI_InitChannel()

    avalonbuffer = zeros(UInt8, 100)  #  This should be more than adequate for 1 byte!

    #sizeToTransfer = packet_length()
    # println("transfer_data length is $transfer_data_length")
    sizeTransfered = Ref{Culong}()

    #  Need an equivalent to writeavalon, call it readavalon.
    bogusbuffer = zeros(UInt8, 1)
    # Transform to Avalon packet:
    #println("Prior to readavalon")
    #  This function is attempting to free invalid pointer.
    #  What is the buffer in the read case???
    readavalon(address, 1, bogusbuffer)
    #println("After readavalon")
    #  Now, get the length of the resultant Avalon packet:
    sizeToTransfer = SPIManager.packet_length()
    println("transfer_data length is $sizeToTransfer")
    buffersize = sizeToTransfer  + 12  #  This is the write packet plus maximum response length.
    #  This is the buffer to be transmitted on the SPI.
    avalonbuffer = unsafe_wrap(Array, SPIManager.get_send_byte_buffer_pointer(),buffersize, own = false)
    #  Create another buffer for the received data:
    readbuffer = zeros(UInt8, 100)
    #  Now, print out the buffer temporarily for debugging.
    for i in 1:12
      #println("avalonbuffer[$i] = $avalonbuffer[i]")
      Printf.@printf("avalonbuffer[%d] = %x\n", i, avalonbuffer[i])
    end

# FT_STATUS SPI_Read(FT_HANDLE handle, uint8 *buffer, uint32 sizeToTransfer, uint32 *sizeTransferred, uint32 transferOptions)

    #  This function needs to write to some buffer.                                                                             Culonglong               Ptr{UInt8}  Ptr(UInt8)    UInt32      Ref(Culong)     UInt32
       spiread = ccall((:SPI_ReadWrite, "libMPSSE"), UInt32, (Culonglong, Ptr{UInt8}, Ptr{UInt8}, UInt32, Ref{Culong}, UInt32), SPIManager.actualhandle, readbuffer, avalonbuffer, buffersize, sizeTransfered, 0)
        #  Return the first byte of the buffer?
       println("spiread = $spiread")

   #    for i in 1:24
   #    println("readbuffer is $readbuffer[i]")
   #    end

       println("The sizeTransfered is $sizeTransfered[]")
       for i in 1:100
         Printf.@printf("readbuffer[%d] = %x\n", i, readbuffer[i])
       end
       SPIManager.SPI_CloseChannel()
    end
