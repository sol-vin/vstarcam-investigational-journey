require "./anti-client"

anti = AntiClient.new
anti.run
sleep 200

 





# client = Client.new
# client.run

# until client.state == :main_phase
#   sleep 0.1
# end

# client.send_udp_get_request("check_user", name: "123456789")
# sleep 3

# sleep 5

# client.close