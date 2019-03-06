require "./client"
client = Client.new
client.run

until client.state == :main_phase
  sleep 0.1
end

client.send_udp_get_request("check_user", name: "123456789")

sleep 5

client.close

# 25.times do |x|
#   VStarCam::LOG.info "RUN #{x}"
#   server = VStarCam.new

#   server.run_server
#   sleep 3
#   x.times {server.send_payload}

#   server.close_server

#   VStarCam::LOG.info "  "
#   VStarCam::LOG.info "  "
#   VStarCam::LOG.info "  "
#   VStarCam::LOG.info "  "

#   sleep 5
# end
