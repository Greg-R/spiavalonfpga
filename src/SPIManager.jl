#  This module replaces the JTAGManager module.
#  This implements the write function.
#  The write function is then used by the send function in the module
#  ImageSerializer.
#  This version uses Julia to create and manage Avalon Packets, instead
#  of the Altera C code.

module SPIManager

export SPI_GetNumChannels, SPI_OpenChannel, SPI_InitChannel, SPI_CloseChannel
export write, writeLEDs

using ProgressMeter
using Printf

include("AvalonPackets.jl")

#  Use ccall to use MPSSE C library functions.
#  Need to wrap all FTDI MPSSE functions in Julia functions.
#  Check for number of channels and report.  This will only work
#  if the FTDI device is plugged into USB and two kernal modules have
#  been removed:
#  sudo rmmod ftdi_sio usbserial
#  Note that this removal process is done by the udev system and a script.
#  Look in the directory /etc/udev/rules.d
#  The module removal is done a boot by a systemd service.

channel = Ref{Cuint}(0)  # pointer to 0

function SPI_GetNumChannels()
    ccall((:SPI_GetNumChannels,"libMPSSE"),UInt32, (Ref{Cuint},), channel)
#  The full path is required if the command ldconfig has not been used to add the path.
#ccall((:SPI_GetNumChannels,"/usr/local/lib/libMPSSE.so"),UInt32, (Ref{Cuint},), channel)
println("Number channels = $channel")
end

#  FTDI MPSSE struct which is used to configure the SPI channel.
struct ChannelConfig_t
    ClockRate::UInt32
    LatencyTimer::UInt8
    configOptions::UInt32
    Pin::UInt32
    reserved::UInt16
end

#  Configure the channel:
SPI_CONFIG_OPTION_MODE0= 0x00000000
SPI_CONFIG_OPTION_CS_DBUS3 =	0x00000000
SPI_CONFIG_OPTION_CS_ACTIVELOW =	0x00000020
configOptions = SPI_CONFIG_OPTION_MODE0 | SPI_CONFIG_OPTION_CS_DBUS3 | SPI_CONFIG_OPTION_CS_ACTIVELOW
Pin = 0x00000000
#  Initialize the struct.  First parameter is clock rate in Hz.  Maximum 30 MHz.
#  The 2nd parameter is the latency timer.  Set this value low for fast ReadWrite.
channelConf = ChannelConfig_t(30000000, 1, configOptions, Pin,0)

#  OPen and Initialize the SPI device.
function SPI_InitChannel()
handle = Ref{UInt32}()  #  This is written to by SPI_OpenChannel function.
opencall =  ccall((:SPI_OpenChannel, "/usr/local/lib/libMPSSE.so"), UInt32, (Cuint, Ref{UInt32}), 0, handle)
println("opencall = $opencall")
Printf.@printf("handle = %x\n", handle[])
initcall = ccall((:SPI_InitChannel, "/usr/local/lib/libMPSSE.so"), UInt32, (UInt32, Ref{ChannelConfig_t}), handle[], channelConf)
println("initcall = $initcall")
return handle[]
end

#  Close the SPI Channel and report.
function SPI_CloseChannel(handle)
spi_close = ccall((:SPI_CloseChannel, "/usr/local/lib/libMPSSE.so"), UInt32, (UInt32,), handle)
println("spiclose = $spi_close")
end

#  Need a "write" function which is similar to that in JTAGManager.
#  This function needs to safely open and close the SPI device channel.
#  This is done using the collection of FTDI MPSSE functions above.

#  This is the main Read/Write/ReadWrite wrapper.  Uncomment the 3 C function variants as required.
function spi_readwrite(handle, read_buf::Array{UInt8,1}, write_buf::Array{UInt8,1}, size)
   sizeTransfered = Ref{UInt32}(0)
   #ftdi_error = ccall((:SPI_Write, "/usr/local/lib/libMPSSE.so"), UInt32, (UInt32, Ptr{UInt8}, UInt32, Ref{UInt32}, UInt32), handle, write_buf, size, sizeTransfered, 0)
   #ftdi_error = @time ccall((:SPI_Read, "/usr/local/lib/libMPSSE.so"), UInt32, (UInt32, Ptr{UInt8}, UInt32, Ref{UInt32}, UInt32), handle, readbuffer, size, sizeTransfered, 0)
   ftdi_error = ccall((:SPI_ReadWrite, "/usr/local/lib/libMPSSE.so"), UInt32, (UInt32, Ptr{UInt8}, Ptr{UInt8}, UInt32, Ref{UInt32}, UInt32), handle, read_buf, write_buf, size, sizeTransfered, 0x00)
   if ftdi_error != 0
    println("FTDI Error!")
   end
   return ftdi_error
end

#  Transaction op codes:
SEQUENTIAL_WRITE = 0x04
SEQUENTIAL_READ  = 0x14
NON_SEQUENTIAL_WRITE = 0x00
NON_SEQUENTIAL_READ = 0x10

#  This is the primary write function which uses FTDI SPI device to write to FPGA Avalon bus.
function write(
            address,
            data
       )

    # Open the channel to the SPI device.
    SPI_GetNumChannels()
    thisHandle = SPI_InitChannel()

    # Compute the number of transfers
    #  This should be the number of individual frames in the animated GIF.
    bytes_per_transfer = 64000  #  Actual will be higher than this due to Avalon packet overhead.
    data_length = length(data)
    ntransfers = ceil(Int, data_length / bytes_per_transfer)
    println("The number ntransfers = $ntransfers")
    println("The image data length is $data_length")
    avalonbuffer2 = zeros(UInt8, 65536)
    readbuffer = zeros(UInt8, 65536)
    #  Alternate ways of creating arrays.
    #    readbuffer = Vector{UInt8}(undef, 66000)
    #    readbuffer = Base.Libc.malloc(166000)
    buffersize = 0
    transfer_data_length = 0

@showprogress for i in 1:ntransfers

        # Compute start address for this transfer
        start = address + bytes_per_transfer * (i-1) # Starts at address
        # Get the index range of data for this transfer
        idx_low = bytes_per_transfer * (i-1) + 1
        idx_high = min(bytes_per_transfer * i, length(data))

        #  This if statement is so the function can handle a single byte.
        if length(data) > 1  #  Required because view will not work on single byte.
        transfer_data = view(data, idx_low:idx_high)
        else
        transfer_data = data
        end

        transfer_data_length = length(transfer_data)

        # Transform to Avalon packet.  See include file AvalonPackets.jl.
        header, header_and_datalength = AvalonPackets.do_transaction(SEQUENTIAL_WRITE, transfer_data_length, start, transfer_data)
        send_data, send_data_length = AvalonPackets.tx_packet(header, header_and_datalength)
        avalonbuffer, buffersize = AvalonPackets.byte_to_core(send_data, send_data_length)

#  Write the data to the FTDI SPI device and thus to the FPGA:
spiwrite = spi_readwrite(thisHandle, readbuffer, avalonbuffer, buffersize)

        #  The data returned by byte_to_core to the avalonbuffer must be analyzed.
        #  It will include a response packet which contains the number of bytes written/read.
        #  The response packet is tacked onto the end.  So back up 12 indices from the end, and that should
        #  be the response packet.  There may be a few idle characters which can be ignored.
        #  Interpret the response.
response_packet = AvalonPackets.clean_response(readbuffer[(buffersize-12):buffersize])
#  This function returns a 16 bit unsigned integer, which should be the number of bytes written.
response_data = AvalonPackets.get_response_data(response_packet)

#  Verify the number of bytes written is what was intended.
if response_data != transfer_data_length
    println("Bad data transfer!!!")
    println("Response data = $response_data")
    println("i = $i")
    println("Buffersize = $buffersize")
    #  Look for possible problems caused by special characters.
    for k in 1:bytes_per_transfer
        if transfer_data[k] == 0x7a
            Printf.@printf("transfer_data[%d] = %x\n", k, transfer_data[k])
        elseif transfer_data[k] == 0x7b
            Printf.@printf("transfer_data[%d] = %x\n", k, transfer_data[k])
        elseif transfer_data[k] == 0x7c
            Printf.@printf("transfer_data[%d] = %x\n", k, transfer_data[k])
        elseif transfer_data[k] == 0x7d
            Printf.@printf("transfer_data[%d] = %x\n", k, transfer_data[k])
        elseif transfer_data[k] == 0x4a
            Printf.@printf("transfer_data[%d] = %x\n", k, transfer_data[k])
        elseif transfer_data[k] == 0x4d
            Printf.@printf("transfer_data[%d] = %x\n", k, transfer_data[k])
        end
    end
end

end # ntransfers
#    for k in (buffersize - 12):buffersize
#            Printf.@printf("readbuffer[%d] = %x\n", k, readbuffer[k])
#        end

#Printf.@printf("buffersize = %d\n", buffersize)

#println("Transfer data length = $transfer_data_length")
SPI_CloseChannel(thisHandle)
end

#  This function was used to debug the write function above.
function writeLEDs(
            address,
            data
       )

       avalonbuffer = zeros(UInt8, 100)
       readbuffer = zeros(UInt8, 100)

    # Open the channel to the SPI device.
    SPI_GetNumChannels()
    thisHandle = SPI_InitChannel()

    transfer_data_length = length(data)
    #    header = AvalonPackets.do_transaction(0x04, transfer_data_length, address, data)
    #    avalonbuffer = AvalonPackets.tx_packet(header)
    #    buffersize = length(avalonbuffer)

    header, header_and_datalength = AvalonPackets.do_transaction(SEQUENTIAL_WRITE, transfer_data_length, address, data)
    send_data, send_data_length = AvalonPackets.tx_packet(header, header_and_datalength)
    avalonbuffer, buffersize = AvalonPackets.byte_to_core(send_data, send_data_length)

        for i in 1:buffersize
        Printf.@printf("avalonbuffer[%d] = %x\n", i, avalonbuffer[i])
        end

        spiwrite = spi_readwrite(thisHandle, readbuffer, avalonbuffer, buffersize)
        println("spiwrite = $spiwrite")
        response_packet = AvalonPackets.clean_response(readbuffer[(buffersize-12):buffersize])
        response_data = AvalonPackets.get_response_data(response_packet)
        println("Response data = $response_data")

        for i in (buffersize - 12):buffersize
        Printf.@printf("readbuffer[%d] = %x\n", i, readbuffer[i])
        end

        for i in 1:length(response_packet)
        Printf.@printf("response_packet[%d] = %x\n", i, response_packet[i])
        end

        println("buffersize = $buffersize")
SPI_CloseChannel(thisHandle)
end

end # module
