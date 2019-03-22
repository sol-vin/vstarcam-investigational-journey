require "logger"
require "socket"

class Client
  STATES = [:nothing,
            :send_dbp, 
            :wait_for_dbr,
            :send_bcp, 
            :wait_for_bps_and_echo,
            :wait_for_bpa,
            :main_phase,
            :closing,
            :closed]

  getter state : Symbol = STATES[0]

  # File location of the log
  LOG_LOCATION = "./vstarcam.log"

  # Open the Log
  # LOG_FILE = File.new(LOG_LOCATION, "w+")
  # LOG = Logger.new(LOG_FILE)

  # The Logger object pointed to STDOUT
  LOG = Logger.new(STDOUT)
  
  # Data socket for UDP connection with camera
  getter data_sock = UDPSocket.new

  # Broadcast socket for discovering new cameras on the network
  getter db_client_sock = UDPSocket.new
  getter db_camera_sock = UDPSocket.new
  getter db_client_sock = UDPSocket.new
  getter bc_camera_sock = UDPSocket.new

  getter target_info : Hash(Symbol, String)
  # Channel that will communicate data back to the tick fiber
  @data_channel = Channel(Tuple(String, Socket::IPAddress)).new

  # Fiber which deals with incoming packet data, holds this data temporarily and then sends the data via @data_channel to the tick fiber.
  @data_fiber : Fiber = spawn {}
  # Fiber which handles the decision process of handling the state of the client. receives incoming data  from data_channel and processes it
  @tick_fiber : Fiber = spawn {} 

  # Source address for the data socket
  DATA_SOCK_SRC = Socket::IPAddress.new("0.0.0.0", 10560)

  # Destination address for the f130 broadcast packet
  BC_SOCK_CLIENT_DST = Socket::IPAddress.new("255.255.255.255", 32108)

  # Source address for the DBP
  DB_SOCK_CLIENT_SRC = Socket::IPAddress.new("0.0.0.0", 6801)
  
  # Destination address for the discovery packet
  DB_SOCK_CLIENT_DST = Socket::IPAddress.new("255.255.255.255", 8600)

  # Listening address for DB requests to the camera.
  DB_SOCK_CAMERA_SRC = Socket::IPAddress.new("0.0.0.0", 8600)

  # Destination address for the DBR 
  DB_SOCK_CAMERA_DST = Socket::IPAddress.new("255.255.255.255", 6801)

  # Listening address for the f130 broadcast packet
  BC_SOCK_CAMERA_SRC = Socket::IPAddress.new("0.0.0.0", 32108)

  #BC_SOCK_CAMERA_DST IS UNKNOWN! We need to wait for a client to connect to us.
  
  # Special uuid which will unblock the data_fiber, allowing the program to exit.
  UNBLOCK_FIBER_DATA = "e127e855-36d2-43f1-82c0-95f2ba5fe800"

  # Discovery packet data
  DBP = "\x44\x48\x01\x01"
  DBR_HEADER = "\x44\x48\x01\x08"
  # Size of the discovery packet reply
  DBR_SIZE = 0x207
  # Regex to check if a packet is a DBR
  DBR_REGEX = /^DH/

  # DBR Fields Packet ranges
  DBR_CAMERA_IP = 0x4..0x13
  DBR_NETMASK = 0x14..0x23
  DBR_GATEWAY = 0x24..0x33
  DBR_DNS1 = 0x34..0x43
  DBR_DNS2 = 0x44..0x53
  DBR_MAC_ADDRESS = 0x54..0x58 # Stored as bytes
  DBR_HTTP_PORT = 0x5a..0x5b   # Stored as Little Endian bytes
  DBR_BIG_I_HTTP_PORT = 0x5b
  DBR_LITTLE_I_HTTP_PORT = 0x5a
  DBR_UID = 0x5b..0x7a
  DBR_NAME = 0x7b..0xca
  DBR_DDNS_IP = 0xcb..0xda
  DBR_UNKNOWN1 = 0x12c
  DBR_UNKNOWN1_DEFAULT = "\x01"
  DBR_DDNS_URL = 0x143..0x1c2
  DBR_SN = 0x1c3..0x1e2
  DBR_DDNS_PASSWORD = 0x1e3..0x1ff
  DBR_UNKNOWN2 = 0x204
  DBR_UNKNOWN2_DEFAULT = "\x02"
  DBR_PORT = 0x206..0x207  # Stored in big endian

  # F130 broadcast packet data
  BCP = "\xf1\x30\x00\x00"

  # F130 broadcast packet reply size
  BPS_HEADER = "\xf1\x41\x00\x14"
  BPA_HEADER = "\xf1\x42\x00\x14"

  # BPR fields ranges
  BPR_UID1 = 0x4..0x0d
  BPR_UID2 = 0xe..0xf     # Stored in Big endian
  BPR_UID3 = 0x10..0x17

  # Fixed BPR size
  BPR_SIZE = 24
  # Character sent for "SYN"
  BP_SYN = 'A'
  # Character sent for "ACK"
  BP_ACK = 'B'

  # Packet that must be sent between the camera and the client at least once every 11 packets
  PING_PACKET = "\xf1\xe0\x00\x00"
  # Packet that must be sent between the camera and the client at least once every 11 packets
  PONG_PACKET = "\xf1\xe1\x00\x00"
  # Packet sent when the camera has timed out from ping-pong
  DISCONNECT_PACKET= "\xf1\xf0\x00\x00"

  REPLY_HEADER = "\xf1\xd1\x00"
  RESPONSE_HEADER = "\xf1\xd0\x00"


  # Are the client fibers currently running?
  getter? is_running = false

  # A list that hold cameras that have completed the handshake.
  getter target = Socket::IPAddress.new("0.0.0.0", 0)
  getter target_info = {} of Symbol => String


  def new_target(socket_ip)
    @target = socket_ip
  end

  # Target a camera.
  def new_target(ip : String, port = 0)
    @target = Socket::IPAddress.new(ip, port)
  end
  
  # Have we found at least one target yet?
  def has_target?
    @target.port != 0
  end

  def initialize
    setup
  end

  # Sets up the client by binding the udp sockets to addresses and ports
  def setup
    # Don't resetup the client if its is_running
    if !is_running?
      LOG.info("Opening ports")
      setup_ports
      LOG.info("Ports opened")
      return
    else
      LOG.error "CANNOT SETUP SERVER WHILE IT IS RUNNING!"
      raise "CANNOT SETUP SERVER WHILE IT IS RUNNING!"
    end
  end

  def setup_ports
    # Our socket for sending UDP data to the camera
    @data_sock.bind DATA_SOCK_SRC
    # Super important to enable this or else we can't broadcast to 255.255.255.255!
    @data_sock.setsockopt LibC::SO_BROADCAST, 1
    # Our socket for sending discovery broadcasts.
    @db_client_sock.bind DB_SOCK_CLIENT_SRC
    @db_client_sock.setsockopt LibC::SO_BROADCAST, 1

    # Our socket for recieving discovery broadcasts and sending DBRs
    @db_camera_sock = UDPSocket.new
    @db_camera_sock.bind DB_SOCK_CAMERA_SRC
    @db_camera_sock.setsockopt LibC::SO_BROADCAST, 1

    # Socket to get BCP
    @bc_camera_sock = UDPSocket.new
    @bc_camera_sock.bind BC_SOCK_CAMERA_SRC
    @bc_camera_sock.setsockopt LibC::SO_BROADCAST, 1
  end

  def run
    # Dont allow the client to run again!
    if !is_running?
      @is_running = true
      # Change the state so it will attempt to discover a camera on the network
      @state = :send_dbp
      #Start our fibers
      start_data_fiber
      start_tick_fiber
    else
      LOG.error "ALREADY RUNNING SERVER!" 
    end
  end

  def close
    LOG.info("Closing client")
    send_disconnect
    sleep 0.1
    @is_running = false
    change_state(:closing)

    # This line unblocks the @data_fiber
    unblock_data
    # Force a fiber change to go to the other fibers to end them
    Fiber.yield

    # Now we can close the sockets
    @data_sock.close
    @db_client_sock.close
    @db_camera_sock.close
    @bc_camera_sock.close

    # Reset the target_camera
    new_target "0.0.0.0", 0
    change_state(:closed)

    LOG.info("Closed client")
  end

  def unblock_data
    @data_sock.send(UNBLOCK_FIBER_DATA, Socket::IPAddress.new("127.0.0.1", DATA_SOCK_SRC.port))
  end

  # Change the state of the client.
  def change_state(state)
    @state = state
    LOG.info "Changing to #{@state}"
    tick # rerun the tick since the state immeadiately changed and there is new stuff to do.
  end

  # Start the fiber which blocks for incoming data, then forwards it to a channel.
  def start_data_fiber
    @data_fiber = spawn do
      begin
        # Only run this fiber while is_running, if not exit
        while is_running?
          # Will block execution
          packet = data_sock.receive
          #LOG.info "received packet from #{packet[1]}"
          @data_channel.send(packet)
        end
      rescue e
        LOG.info "DATA EXCEPTION #{e}"
        close
      end
    end
  end

  # Start the fiber which contains the tick logic.
  def start_tick_fiber
    @tick_fiber = spawn do
      begin
        # Only run this fiber while is_running, if not exit
        while is_running?
          tick
        end
      rescue e
        LOG.info "TICK EXCEPTION #{e}"
        close
      end
    end
  end

  # Main decision making function
  def tick
    if state == :nothing
      # Do nothing
    elsif state == :send_dbp
      send_dbp
      change_state(:wait_for_dbr)
    elsif state == :wait_for_dbr
      info = wait_for_dbr
      if info
        @target_info = info
        change_state(:send_bcp)
      else
        change_state(:send_dbp)
      end
    elsif state == :send_bcp
      send_bcp
      change_state :wait_for_bps_and_echo
    elsif state == :wait_for_bps_and_echo
      wait_for_bps_and_echo
      change_state(:wait_for_bpa)

    elsif state == :wait_for_bpa
      if wait_for_bpa
        change_state :main_phase
      else
        change_state :send_dbp
      end
    elsif state == :main_phase
      # Do ping pong, etc in here
      main_phase
    elsif state == :closing
      # do nothing
    elsif state = :closed
      # do nothing
    else
      raise "THERE WAS A BAD IN TICK!"
    end
  end

  # Send the DBP to the camera
  def send_dbp
    LOG.info("Sending DBP")
    db_client_sock.send(DBP, DB_SOCK_CLIENT_DST)
    LOG.info("Sent DBP")
  end

  # Wait for the DBR to come back from the camera.
  def wait_for_dbr : Hash(Symbol, String)?
    # TODO: ADD TIMEOUTS!
    LOG.info("Waiting for DBR")
    packet = db_client_sock.receive
    if packet
      if self.class.check_dbr(packet)
        info = self.class.parse_dbr(packet)
        LOG.info("DBR RECEIVED FROM #{packet[1]}, UID: #{info[:uid]}")
        return info
      else
        LOG.info("BAD/NON DBR RECEIVED! #{packet[0].bytes.map {|d| d.to_s(16).rjust(2, '0')}.join("\\x")}")
      end
    else
      LOG.info("NO DBR RECEIVED!")
    end

    return nil
  end

  # Check if the packet we received was a DBR
  def self.check_dbr(packet) : Bool
    !!(packet[0] =~ DBR_REGEX)
  end

  # Parse the DBR information into a hash
  def self.parse_dbr(packet) : Hash(Symbol, String)
    data = packet[0]
    connection = packet[1]

    result = {} of Symbol => String

    result[:camera_ip] = data[DBR_CAMERA_IP].gsub("\x00", "")
    result[:netmask] = data[DBR_NETMASK].gsub("\x00", "")
    result[:gateway] = data[DBR_GATEWAY].gsub("\x00", "")
    result[:dns1] = data[DBR_DNS1].gsub("\x00", "")
    result[:dns2] = data[DBR_DNS2].gsub("\x00", "")
    result[:mac_address] = (data[DBR_MAC_ADDRESS].bytes.map {|b| b.to_s(16).rjust(2, '0').upcase}).join(':')
    result[:http_port] = ((data.bytes[DBR_BIG_I_HTTP_PORT].to_i32 << 8) + data.bytes[DBR_LITTLE_I_HTTP_PORT].to_i).to_s
    result[:uid] = data[DBR_UID].gsub("\x00", "")
    result[:name] = data[DBR_NAME].gsub("\x00", "")
    result[:ddns_ip] = data[DBR_DDNS_IP].gsub("\x00", "")
    result[:unknown1] = data[DBR_UNKNOWN1].to_s
    result[:ddns_url] = data[DBR_DDNS_URL].gsub("\x00", "")
    result[:sn] = data[DBR_SN].gsub("\x00", "")
    result[:ddns_password] = data[DBR_DDNS_PASSWORD].gsub("\x00", "")
    #result[:unknown2] = data[DBR_UNKNOWN2].to_s
    #result[:port] = ((data[DBR_PORT].bytes[0] << 8) + data[DBR_PORT].bytes[1]).to_s
    LOG.info("Parsed new target camera #{result}")
    result
  end

  # Makes a DBR given a dbr_hash
  def self.make_dbr(dbr_hash) : String
    dbr = DBR_HEADER
    # Need to ljust for \x00 padding
    dbr += dbr_hash[:camera_ip].ljust(DBR_CAMERA_IP.size,"\x00"[0])
    dbr += dbr_hash[:netmask].ljust(DBR_NETMASK.size,"\x00"[0])
    dbr += dbr_hash[:gateway].ljust(DBR_GATEWAY.size,"\x00"[0])
    dbr += dbr_hash[:dns1].ljust(DBR_DNS1.size,"\x00"[0])
    dbr += dbr_hash[:dns2].ljust(DBR_DNS2.size,"\x00"[0])
    dbr += dbr_hash[:mac_address].split(':').map {|byte| String.new(Bytes[byte.to_i(16)])}.join
    little_i = (dbr_hash[:http_port].to_i & 0x00ff)
    big_i = (dbr_hash[:http_port].to_i & 0xff00) >> 8
    #pp dbr_hash[:mac_address].split(':').map {|byte| String.new(Bytes[byte.to_i(16)])}.join.bytes.map {|b| "0x" + b.to_s 16}
    dbr += String.new(Bytes[little_i, big_i])
    dbr += dbr_hash[:uid].ljust(DBR_UID.size,"\x00"[0])
    dbr += dbr_hash[:name].ljust(DBR_NAME.size,"\x00"[0])
    dbr += dbr_hash[:ddns_ip].ljust(DBR_DDNS_IP.size,"\x00"[0])
    dbr += "\x00" * 0x51
    dbr += dbr_hash[:unknown1] # Single byte
    dbr += "\x00" * 0x16
    dbr += dbr_hash[:ddns_url].ljust(DBR_DDNS_URL.size,"\x00"[0])
    dbr += dbr_hash[:sn].ljust(DBR_SN.size,"\x00"[0])
    dbr += dbr_hash[:ddns_password].ljust(DBR_DDNS_PASSWORD.size,"\x00"[0])
    dbr += "\x00"*3
    dbr += DBR_UNKNOWN2_DEFAULT # Single byte
    dbr += "\x00"
    little_i = (DB_SOCK_CAMERA_DST.port & 0x00ff)
    big_i = (DB_SOCK_CAMERA_DST.port  & 0xff00) >> 8
    dbr += String.new(Bytes[big_i, little_i])
    dbr += "\xff" * 4
    dbr
  end

  def send_dbr(dbr_hash : Hash(Symbol, String))
    dbr = Client.make_dbr(dbr_hash)
    send_dbr dbr
  end

  def send_dbr(dbr_string : String)
    @db_camera_sock.send(dbr_string, DB_SOCK_CAMERA_DST)
  end

  # Send the magic f130 broadcast packet
  def send_bcp
    data_sock.send(BCP, BC_SOCK_CLIENT_DST)
  end

  def wait_for_bps_and_echo
    LOG.info("Waiting for BPS")
    packet = receive_bps
    LOG.info("received a packet")

    if packet
      data = packet[0]  # Contains the packet data
      camera_ip = packet[1] # Connection info to connect back into the camera (ip, port)
      LOG.info("BPS Verified!")
      data_sock.send(data, camera_ip)        
      return true
    end
    return false
  end

  def self.make_bps(uid)
    bps = BPS_HEADER
    bps += uid[0x0..0x3]
    bps += "\x00" * 5
    uid2 = uid[0x4..0x9].to_i
    bps += String.new(Bytes[(uid2 & 0xff0000) >> 16, (uid2 & 0xff00) >> 8, uid2 & 0xff])
    bps += uid[0xa..0xf]
    bps += "\x00"*3
    bps
  end

  def self.parse_bps(uid)
    #TODO: MAKE THIS WORK!
  end

  def send_bps(uid)
    bps = Client.make_bps uid
    @data_sock.send(bps, target)
  end

  def receive_bps
    got_bps = false
    until got_bps
      potential_bps = @data_channel.receive
      if potential_bps[0][0..3] == BPS_HEADER
        got_bps = true
      end
    end
    potential_bps
  end

  def receive_bps(timeout)
    bps_channel = Channel(Bool).new

    main_fiber = spawn do
      got_bps = false
      until got_bps
        potential_bps = @data_channel.receive
        if potential_bps[0][0..3] == BPS_HEADER
          got_bps = true
        elsif potential_bps[0] == UNBLOCK_FIBER_DATA
          break
        end
      end
      bps_channel.send got_bps
    end

    timeout_fiber = spawn do
      sleep timeout
      unblock_data if is_running?
    end

    got_bps = bps_channel.receive
    if got_bps
      LOG.info "BPS SUCCESSFUL" 
    else
      LOG.info "BPS UNSUCCESSFUL"
    end
    got_bps
  end

  def wait_for_bpa
    LOG.info("Waiting for BPA")
    packet = receive_bpa
    LOG.info("received a packet")

    if packet
      data = packet[0]  # Contains the packet data
      camera_ip = packet[1] # Connection info to connect back into the camera (ip, port)
      LOG.info("BPA Verified! Handshake Successful!")
      new_target camera_ip    
      return true
    end
    return false
  end

  def self.make_bpa(uid)
    bpa = BPA_HEADER
    bpa += uid[0x0..0x3]
    bpa += "\x00" * 5
    uid2 = uid[0x4..0x9].to_i
    bpa += String.new(Bytes[(uid2 & 0xff0000) >> 16, (uid2 & 0xff00) >> 8, uid2 & 0xff])
    bpa += uid[0xa..0xf]
    bpa += "\x00"*3
    bpa
  end

  def send_bpa(uid)
    bpa = Client.make_bpa uid
    @data_sock.send(bpa, target)
  end

  def receive_bpa
    got_bpa = false
    until got_bpa
      potential_bpa = @data_channel.receive
      if potential_bpa[0][0..3] == BPA_HEADER
        got_bpa = true
      end
    end
    potential_bpa
  end

  def main_phase
    # Block here to receive data from the data fiber
    data = @data_channel.receive

    # Classify each packet and respond
    if data[0] == PING_PACKET
      send_pong
    elsif data[0] == PONG_PACKET
      send_ping
    elsif data[0] == DISCONNECT_PACKET
      LOG.info "RECEIVED DISCONNECT FROM CAMERA"
      close
    elsif data[0][0..2] == REPLY_HEADER
      LOG.info "REPLY RECIEVED FROM CAMERA"
    elsif data[0][0..2] == RESPONSE_HEADER
      LOG.info "RESPONSE RECIEVED FROM CAMERA #{data[0].size}"   
      LOG.info "\n" + data[0][0x10..data[0].size]
      send_reply
    # This is important! The data fiber will block, waiting for data to come through
    # So to exit the program, we just send the unblock data to the data socket to free it
    elsif data[0][0..3] == BPA_HEADER
      LOG.info "Receive extra BPA"
    elsif data[0] == UNBLOCK_FIBER_DATA
      LOG.info "RECEIVED UNBLOCK FIBER COMMAND!"
    else
      LOG.info "UNKNOWN PACKET RECEIVED from #{data[1]} : #{data[0].bytes.map {|d| d.to_s(16).rjust(2, '0')}.join("\\x")}"
    end
  end

  def send_ping
    data_sock.send(PING_PACKET, target)
    LOG.info "Sent Ping"
  end

  def send_pong
    data_sock.send(PONG_PACKET, target)
    LOG.info "Sent Pong"
  end

  def send_disconnect
    data_sock.send(DISCONNECT_PACKET, target)
    LOG.info "Sent Disconnect"
  end

  # Camera to client
  #           Bytes in reply  Packet concerning
  #                |               |
  # "\xf1\xd1\x00\x08\xd1\x00\x00\x02\x00\x00\x00\x00"

  # Client to camera
  #           Bytes in reply  Packet concerning
  #                |               |
  # "\xf1\xd1\x00\x06\xd1\x00\x00\x01\x00\x00"

  # Multipart ack reply
  # "\xf1\xd1\x00\x18\xd1\x00\x00\x0a\x00\x0f\x00\x10\x00\x11\x00\x12"
  # "\x00\x13\x00\x14\x00\x15\x00\x16\x00\x17\x00\x18"


  @replies_sent = 0

  def make_reply
    reply = REPLY_HEADER
    reply += "\x06" # REPLY BYTES
    reply += "\xd1"
    reply += "\x00"
    reply += "\x00"
    reply += "\x01"
    reply += "\x00"
    reply += String.new(Bytes[@replies_sent])
    reply
  end

  def send_reply
    reply = make_reply
    @data_sock.send(reply, target)
    @replies_sent += 1
  end

  # Single response header
  # "\xf1\xd0\x00\x48\xd1\x00\x00\x00\x01\x0a\xa0\x60\x3c\x00\x00\x01" \


  # This is an example header for when the camera sends a multipart response
  # This example had data sizes of 1032, 1032, 1032, 728
  # Multipacket header breakdown
  #       Total size of packet   Total requests      Total Size of all packets                  
  #              |      |             |                  |      |       
  # 1 : "\xf1\xd0\x04\x04\xd1\x00\x00\x0b\x01\x0a\x02\x60\xc8\x0e\x00\x01" 
  # 2 : "\xf1\xd0\x04\x04\xd1\x00\x00\x0c"
  # 3 : "\xf1\xd0\x04\x04\xd1\x00\x00\x0d"
  # 4 : "\xf1\xd0\x02\xd4\xd1\x00\x00\x0e"

  def send_response(response)
  end

  USER = "admin"
  PASS = "password"
  LOGIN_PARAMS = "&loginuse=#{USER}&loginpas=#{PASS}&user=#{USER}&pwd=#{PASS}"

  @requests_sent = 0

  def make_udp_header(get_request)
    "\xf1\xd0#{String.new(Bytes[get_request.size + 0xc]).rjust(2, "\x00"[0])}\xd1\x00#{String.new(Bytes[@requests_sent]).rjust(2, "\x00"[0])}" 
  end

  def make_get_request_header(get_request)
    "\x01\x0a\x00#{String.new(Bytes[get_request.size]).rjust(2, "\x00"[0])}\x00\x00\x00"
  end

  def send_udp_get_request(cgi : String, **params)
    param_string = params.keys.map{|param_name|"#{param_name}=#{params[param_name]}"}.join('&')
    get_request = "GET /#{cgi}.cgi?#{param_string}#{LOGIN_PARAMS}"
    header = make_udp_header(get_request)
    request_header = make_get_request_header(get_request)
    data_sock.send(header + request_header + get_request, target)
    @requests_sent += 1
    LOG.info "SENT #{get_request}"
  end

  def send_udp_raw_get_request(request : String, **params)
    param_string = params.keys.map{|param_name|"#{param_name}=#{params[param_name]}"}.join('&')
    get_request = "GET #{request}?#{param_string}"
    header = make_udp_header(get_request)
    request_header = make_get_request_header(get_request)
    data_sock.send(header + request_header + get_request, target)
    @requests_sent += 1
    LOG.info "SENT #{get_request}"
  end

  # def send_udp_raw_get_request(request : String)
  #   get_request = "GET #{request}"
  #   header = make_udp_header(get_request)
  #   request_header = make_get_request_header(get_request)
  #   data_sock.send(header + request_header + get_request, target)
  #   @requests_sent += 1
  #   LOG.info "SENT #{get_request}"
  # end
end