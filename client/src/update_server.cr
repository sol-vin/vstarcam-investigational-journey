require "kemal"
require "./ifconfig"

get "/update" do |env|
  send_file env, "rsrc/update"
end
Kemal.config.port = 80
Kemal.run