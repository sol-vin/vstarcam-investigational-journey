module IfConfig
  def self.get
    ifconfig_original = `ifconfig`

    ifconfig_original = ifconfig_original.lines.reject { |l| l.includes? "inet6"}
    #ifconfig_original.lines.grep(/ether/)[0].match(/([0-9a-f]{2}\:){5}[0-9a-f]{2}/)

    interfaces = [] of Interface

    ifconfig_original.each_with_index do |line, index|
      interface_line = index % 8
      if interface_line == 0
        interfaces << Interface.new
        interfaces.last.name = line.split(":")[0].strip
      elsif interface_line == 1
        if line.split("broadcast").size == 2
          interfaces.last.broadcast = line.split("broadcast")[1].strip
        end
        if line.split("inet").size == 2
          interfaces.last.ipv4_address = line.split("inet")[1].split("netmask")[0].strip
          interfaces.last.netmask = line.split("netmask")[1].split("broadcast")[0].strip
        end
        if line.split("ether").size == 2
          interfaces.last.mac_address = line.split("ether")[1].split("txqueuelen")[0].strip
        end
      elsif interface_line == 2
        if line.split("ether").size == 2
          interfaces.last.mac_address = line.split("ether")[1].split("txqueuelen")[0].strip
        end
      end
    end
    interfaces
  end
end

class Interface
  property name : String = ""
  property ipv4_address : String = ""
  property netmask : String = ""
  property broadcast : String = ""
  property mac_address : String = "" 
end