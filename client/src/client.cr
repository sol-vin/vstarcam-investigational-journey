require "logger"
require "socket"
require "./helpers"

class Client
  STATES = [:nothing,
            :send_dbp, 
            :wait_for_dbr,
            :send_bcp, 
            :handle_bp_handshake,
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
  DBR_MAC_ADDRESS = 0x54..0x59 # Stored as bytes
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
  #DBR_UNKNOWN2 = 0x204
  #DBR_UNKNOWN2_DEFAULT = "\x02"
  #DBR_PORT = 0x206..0x207  # Stored in big endian

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
    @data_sock.send(UNBLOCK_FIBER_DATA, Socket::IPAddress.new("127.0.0.1", DATA_SOCK_SRC.port))
    # Force a fiber change to go to the other fibers to end them
    Fiber.yield

    # Now we can close the sockets
    @data_sock.close
    @db_client_sock.close


    # Reset the target_camera
    new_target "0.0.0.0", 0
    change_state(:closed)

    LOG.info("Closed client")
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
          LOG.info "received packet from #{packet[1]}"
          @data_channel.send(packet)
        end
      rescue e
        LOG.info "DATA EXCEPTION #{e}"
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
      end
    end
  end

  # Main decision making function
  def tick
    if state == :nothing
      # Do nothing
    elsif state == :send_dbp
      send_dbp
      change_state :wait_for_dbr
    elsif state == :wait_for_dbr
      info = wait_for_dbr
      if info
        @target_info = info
        change_state :send_bcp
      else
        change_state :send_dbp
      end
    elsif state == :send_bcp
      send_bcp
      change_state :handle_bp_handshake
    elsif state == :handle_bp_handshake
      handle_bp_handshake

      if has_target?
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

  # Send the magic f130 broadcast packet
  def send_bcp
    data_sock.send(BCP, BC_SOCK_CLIENT_DST)
  end

  # Complete the handshake using BPS
  def handle_bp_handshake
    LOG.info("Waiting for BPS")
    packet = @data_channel.receive 
    LOG.info("received a packet")

    if packet
      
      data = packet[0]  # Contains the packet data
      camera_ip = packet[1] # Connection info to connect back into the camera (ip, port)

      LOG.info("received a potential BPS from #{camera_ip}") 
      # Check if out BPR is actually a BPR
      if data[1] == BP_SYN
        LOG.info("BPS Verified!")
      else
        LOG.info("BPS BAD! #{"\\x" + data.bytes.map {|d| d.to_s(16).rjust(2, '0')}.join("\\x")}")
        return
      end

      # Echo back packet data back
      LOG.info("Waiting for BPA")
      data_sock.send(data, camera_ip)
      # Recv the BPR ACK packet
      packet = @data_channel.receive
      if packet
        LOG.info("received potential BPA?")
        data = packet[0]
        camera_ip = packet[1]

        if data[1] == BP_ACK
          LOG.info("BPA Verified! Handshake successful!")
          # set the target camera to the current connection
          new_target camera_ip
        else
          LOG.info("BPA BAD! #{data.bytes.map {|d| d.to_s(16).rjust(2, '0')}.join("\\x")}")
        end
      end
    end
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
end
