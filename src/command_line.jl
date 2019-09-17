#  ArgParse
using ArgParse
using spiavalonfpga
using ProgressMeter

function parse_commandline()
s = ArgParseSettings()
@add_arg_table s begin
    #=
    "--opt1"
        help = "an option with an argument"
    "--opt2", "-o"
        help = "another option with an argument"
        arg_type = Int
        default = 0
    "--flag1"
        help = "an option without argument, i.e. a flag"
        action = :store_true
        =#
    "arg1"
        help = "rotator position"
        arg_type = Int
        required = true
end
return parse_args(s)
end

function rotator()
    parsed_args = parse_commandline()
    println("Parsed args:")
    for (arg,val) in parsed_args
        println("  $arg  =>  $val")
    end
    println(parsed_args["arg1"])
    buffer=zeros(UInt8, 1)
    buffer[1] = parsed_args["arg1"]
    spiavalonfpga.SPIManager.writeLEDs(0x0400_0000, buffer)
#    @showprogress for i in 1:5
#    read_back = spiavalonfpga.SPIManager.readbyte(0x0400_0000)
#    println("Read back of motor position = $read_back")
#    end
    while ((position = spiavalonfpga.SPIManager.readbyte(0x0400_0000)) != buffer[1])
        println("Rotation in Progress")
    end
    position = spiavalonfpga.SPIManager.readbyte(0x0400_0000)
    println("Confirming position is $position.")
end

rotator()
