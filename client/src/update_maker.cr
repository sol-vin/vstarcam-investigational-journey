SENTINEL_VALUE = "www.object-camera.com.by.hongzx."
SENTINEL_VALUE_RANGE = 0x00..0x1f

UPDATE_OFFSET = 0x20
HEADER_OFFSET_DIRECTORY = 0x00..0x3F
HEADER_OFFSET_FILENAME = 0x40..0x7F
HEADER_OFFSET_SIZE = 0x80..0x83
HEADER_OFFSET_VERSION_NUMBER = 0x84..0x8B
HEADER_OFFSET_ZIP_BEGIN = 0x8C

FILE_ORDER_PATH = "client/rsrc/file_order"
FIRMWARE_PATH = "client/rsrc"
ZIP_PATH = "client/rsrc/zip"
NEW_UPDATE_PATH = "client/rsrc/update"
FWVERSION_PATH = "client/rsrc/system/system/bin/fwversion.bin"

# Start construction
fwversion =  File.open(FWVERSION_PATH, "r") {|f| f.read_bytes(Int64, IO::ByteFormat::LittleEndian)}

new_update = File.open(NEW_UPDATE_PATH, "w")
new_update << SENTINEL_VALUE

#Go through each file, turn it into a zip file, then make headers
# files = [] of String
# Dir["#{FIRMWARE_PATH}/system/**/**"].each do |e|
#   files << e.gsub(FIRMWARE_PATH, "") unless File.directory? e
# end

files = File.read(FILE_ORDER_PATH).lines
puts "Loading files for update #{fwversion.to_s(16).rjust(16, '0')}"
puts
files.each do |file_path|
  filename = File.basename file_path
  zip_filename = filename += ".zip"

  # Make zip

  `cd #{FIRMWARE_PATH}; zip zip/#{zip_filename} #{file_path}`
  zip_file = File.read("#{ZIP_PATH}/#{zip_filename}")
  new_update << (File.dirname(file_path) + "/").ljust(HEADER_OFFSET_DIRECTORY.size, "\x00"[0])
  new_update << zip_filename.ljust(HEADER_OFFSET_FILENAME.size, "\x00"[0])

  new_update.write_bytes(zip_file.bytes.size, IO::ByteFormat::LittleEndian)
  new_update.write_bytes(fwversion, IO::ByteFormat::LittleEndian)

  new_update << zip_file

  puts "#{file_path}"
  puts "SIZE: #{zip_file.bytes.size.to_s 16}"
end

new_update << SENTINEL_VALUE.reverse

new_update.close
