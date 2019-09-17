#  SPI Read function

export read

#  This is the primary read function which uses FTDI SPI device to write to FPGA Avalon bus.
#  This is a slight variant of the write function.
function readbyte(
            address
       )

    # Open the channel to the SPI device.
    SPI_GetNumChannels()
    thisHandle = SPI_InitChannel()

    avalonbuffer2 = zeros(UInt8, 128)
    readbuffer = zeros(UInt8, 128)
    #  Alternate ways of creating arrays.
    #    readbuffer = Vector{UInt8}(undef, 66000)
    #    readbuffer = Base.Libc.malloc(166000)
    buffersize = 0

        #  This if statement is so the function can handle a single byte.
        #if length(data) > 1  #  Required because view will not work on single byte.
        #transfer_data = view(data, idx_low:idx_high)
        #else
        #transfer_data = data
        # end

        #  Make a fake placeholder data buffer.
        transfer_data = zeros(UInt8, 1)

        #  A read transaction has 0 data to send.
        transfer_data_length = 1

        # Transform to Avalon packet.  See include file AvalonPackets.jl.
        # Data should be ignored for a Read packet.
        header, header_and_datalength = AvalonPackets.do_transaction(NON_SEQUENTIAL_READ, transfer_data_length, address, transfer_data)
        send_data, send_data_length = AvalonPackets.tx_packet(header, header_and_datalength)
        avalonbuffer, buffersize = AvalonPackets.byte_to_core(send_data, send_data_length)

#        for i in 1:buffersize
          #println("avalonbuffer[$i] = $avalonbuffer[i]")
#          Printf.@printf("avalonbuffer[%d] = %x\n", i, avalonbuffer[i])
#        end

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
#println("Response data = $response_data")
#for i in 1:length(response_packet)
#Printf.@printf("response_packet[%d] = %x\n", i, response_packet[i])
#end

#for i in 1:23
#Printf.@printf("readbuffer[%d] = %x\n", i, readbuffer[i])
#end

#for i in 1:12
#Printf.@printf("response_packet[%d] = %x\n", i, response_packet[i])
#end

read_data = AvalonPackets.get_readback_data(response_packet)
#Printf.@printf("Returned data = %x\n", read_data)

#    for k in (buffersize - 12):buffersize
#            Printf.@printf("readbuffer[%d] = %x\n", k, readbuffer[k])
#        end

#Printf.@printf("buffersize = %d\n", buffersize)

#println("Transfer data length = $transfer_data_length")
SPI_CloseChannel(thisHandle)
return read_data
end
