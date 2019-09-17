module AvalonPackets

#  This module has functions to create and manipulate Avalon Packets.

export do_transaction, tx_packet, get_readback_data
export SEQUENTIAL_WRITE, analyze_response

using Printf

#  Special Packet characters
SOP = 0x7a
EOP = 0x7b
CHANNEL = 0x7c
ESC = 0x7d

#  There is a 3-step process to creating a packet.
#  do_transaction:  Simply glues an Avalon header to the data.
#  tx_packet:  Inserts special characters where required.
#

#  Transaction op codes (for reference):
SEQUENTIAL_WRITE = 0x04
SEQUENTIAL_READ  = 0x14
NON_SEQUENTIAL_WRITE = 0x00
NON_SEQUENTIAL_READ = 0x10

HEADER_LENGTH = 8
RESPONSE_LENGTH = 4

#  This function simply attaches an Avalon packet header to the data.
function do_transaction(type, size, address, data)

    if ((type == SEQUENTIAL_WRITE) | (type == NON_SEQUENTIAL_WRITE) | (type == SEQUENTIAL_READ) | (type == NON_SEQUENTIAL_READ))
      transaction = zeros(UInt8, (size + HEADER_LENGTH))
#transaction = Array{UInt8,1}(UndefInitializer(), size + HEADER_LENGTH)
    end

    #  Make header:
    transaction[1] = type
    transaction[2] = 0x00
    transaction[3] = (size >> 8) & 0xff  #  Works exactly like C?
    transaction[4] = (size & 0xff)
    transaction[5] = (address >> 24) & 0xff
    transaction[6] = (address >> 16) & 0xff
    transaction[7] = (address >>  8) & 0xff
    transaction[8] = (address & 0xff)

    #  Load the data into the transaction:
    if((type == SEQUENTIAL_WRITE) | (type == NON_SEQUENTIAL_WRITE))
    for i in 9:(size + HEADER_LENGTH)
        transaction[i] = data[i - HEADER_LENGTH]
    end
end


    length = size + 8
    return transaction, length

end # do_transaction

#  Complete the Transmit packet.  Pass in the result from do_transaction.
#  The address is already included in the data's header.
#  This function will insert the special characters.
function tx_packet(data, data_length)
#  Response data is a fixed value of 2 bytes to form a 16 bit unsigned integer,
#  which is the number of bytes transmitted or received.  This is the data
#  returned by the Avalon response packet.
#  There are 4 bytes total in the response.  The first byte is the transaction
#  op code with the MSB bit inverted.  The 2nd byte is a "reserved for future use".
response_length = 4

# data_length = length(data)
#println("data_length = $data_length")
send_max_length = 2 * data_length + 4
response_max_length = 2 * response_length + 4

#  Buffers.  Make sure all buffers are initialized to zero!
#  Stray special characters in uninitialized memory can wreak havoc!
send_packet = zeros(UInt8, send_max_length + response_max_length)
#  response_packet = zeros(UInt8, response_max_length)

#  Set up header
send_packet[1] = SOP
send_packet[2] = CHANNEL
send_packet[3] = 0x00

#  Build the packet, adding in special Packet characters as required.
#  Have to also track position in send_packet.
#  This was done with tricky pointer math in original C code.
j = 4  #  This is the index of send_packet. First 3 indices already filled.
for i in 1:data_length
#    println("j = $j")
    current_byte = data[i]
    #  Add EOP before the last byte
    if i == (data_length) #  This is the last loop.
        send_packet[j] = EOP
        j += 1
        send_packet[j] = current_byte  #  Last data byte.
    end
    if current_byte == SOP
        send_packet[j] = ESC
        j += 1
        send_packet[j] = xor_20(current_byte)
        j += 1
    elseif current_byte == EOP
        send_packet[j] = ESC
        j += 1
        send_packet[j] = xor_20(current_byte)
        j += 1
    elseif current_byte == CHANNEL
        send_packet[j] = ESC
        j += 1
        send_packet[j] = xor_20(current_byte)
        j += 1
    elseif current_byte == ESC
        send_packet[j] = ESC
        j += 1
        send_packet[j] = xor_20(current_byte)
        j += 1
    else
        send_packet[j] = current_byte
        j += 1
    end
end
#println("j = $j")  #  j should be length of packet

#    for i in 1:j
#    Printf.@printf("send_packet[%d] = %x\n", i, send_packet[i])
#    end
    length = j - 1 + response_max_length  # Compute the length after inserting special characters.
    return send_packet[1:length], length  # TEMPORARY Need to use response length!!!
end

 BYTESIDLECHAR = 0x4a
 BYTESESCCHAR  = 0x4d

function byte_to_core(send_data, data_length)

#data_length = length(send_data)
send_max_length = 2 * data_length + 4

send_packet = zeros(UInt8, send_max_length)
#send_packet = Array{UInt8,1}(undef, send_max_length)

j = 1
for i in 1:data_length
    current_byte = send_data[i]
    if current_byte == BYTESIDLECHAR
        send_packet[j] = BYTESESCCHAR
        j += 1
        send_packet[j] = xor_20(current_byte)
        j += 1
    elseif current_byte == BYTESESCCHAR
        send_packet[j] = BYTESESCCHAR
        j += 1
        send_packet[j] = xor_20(current_byte)
        j += 1
    else
        send_packet[j] = current_byte
        j += 1
    end
end
length = j - 1  #  Compute the length after inserting special characters.
return send_packet[1:length], length
end

function xor_20(val::UInt8)
    return xor(val,0x20)
end

function clean_response(response_data)
    #  The response packet will always be ? bytes long. Use 12 for now.
    response_packet = zeros(UInt8, 12)
    j = 1
    i = 1
    #  This loop cleans out the idles, which are removed, and removes escapes plus XORing the following byte.
    while j < 13
        current_byte = response_data[j]
        #  Must XOR packets which are preceded by certain special characters.
        if response_data[j] == BYTESIDLECHAR#  Skip and don't write anything to response packet.
            j += 1  #  Skip over the idle.
            continue
        elseif response_data[j] == BYTESESCCHAR
            response_packet[i] = xor(response_data[j + 1]) #  XOR the byte AFTER the escape!
            j += 2 #  jump escape and following byte.
        else
            response_packet[i] = current_byte
            j += 1
        end
        i += 1
    #    Printf.@printf("current_byte = %x\n", current_byte)
    end
    #  Print the response packet:
#    for i in 1:12
#Printf.@printf("response_packet[%d] = %x\n", i, response_packet[i])
#    end
    return response_packet #  This should return the entire packet plus 12 zeros which account for the response, which must be clocked out.
end

#  This function extracts the response data payload.
#  Note on the response data.  The first byte is the op-code with most signiificant bit
#  reversed.  For example, SEQUENTIAL_WRITE = 0x04 with MSB reversed is 0x84.
#  The 2nd byte is reserved; the 3rd and 4th bytes is the 16 bit length of the transaction.
function get_response_data(response_packet)
    data = zeros(UInt16, 12)
i = 1
j = 1
#  First, find SOP and increment i to next byte after.
while i < 12
    current_byte = response_packet[i]
    if response_packet[i] == SOP
        i += 1
        break #  Does this break out of while loop?
    end
    i += 1
end
while i < 12
    current_byte = response_packet[i]
    if response_packet[i] == SOP
        i += 1
        data[j] = xor_20(response_packet[i])
        j += 1
    elseif response_packet[i] == CHANNEL
     i += 2  # Skip special byte and following channel number.
     elseif response_packet[i] == EOP
     # Check to see if byte after EOP is an escape:
       if response_packet[i + 1]  == BYTESESCCHAR
         data[j] = xor_20(response_packet[i+2])
       else
         data[j] = response_packet[i + 1]  #  Byte after EOP.
         i = 13  #  Force break from while loop.
       end
     else
     data[j] = current_byte
     i += 1
     j += 1
 end
 end
# for i in 1:4
#Printf.@printf("data[%d] = %x\n", i, data[i])
# end

 bytes_written::UInt16 = (data[3] << 8) | data[4]
# Printf.@printf("Number of bytes written = %d\n", bytes_written)

 return bytes_written
end

function get_readback_data(avalon_packet)
    read_data = 0x00
    i = 1
    for i in 1:12
        if avalon_packet[i] == EOP
            read_data = avalon_packet[i+1]
            break
        end
    end
    return read_data
end

end # module
