
module Helpers

  # def self.u8_to_bytechar(uint) : String
  #   case uint
  #     when (0x0..0x7F)
  #       uint.chr.to_s
  #     {% for char in (0x80..0xFF) %}
  #       when {{char}}
  #         "\x{{char}}"
  #     {% end %}
  #     else
  #       "???"
  #   end
  # end

  def self.bytes_to_string(uint)
  end


  def self.u16_to_bytechars(uint) : String
    case uint
      when (0x0..0x7F)
        uint.chr.to_s
      when 0x80
        "\x80"
      when 0x81
        "\x81"
      when 0x82
        "\x82"
      when 0x83
        "\x83"
      when 0x84
        "\x84"
      when 0x85
        "\x85"
      when 0x86
        "\x86"
      when 0x87
        "\x87"
      when 0x88
        "\x88"
      when 0x89
        "\x89"
      when 0x8a
        "\x8a"
      when 0x8b
        "\x8b"
      when 0x8c
        "\x8c"
      when 0x8d
        "\x8d"
      when 0x8e
        "\x8e"
      when 0x8f
        "\x8f"
      when 0x90
        "\x90"
      when 0x91
        "\x91"
      when 0x92
        "\x92"
      when 0x93
        "\x93"
      when 0x94
        "\x94"
      when 0x95
        "\x95"
      when 0x96
        "\x96"
      when 0x97
        "\x97"
      when 0x98
        "\x98"
      when 0x99
        "\x99"
      when 0x9a
        "\x9a"
      when 0x9b
        "\x9b"
      when 0x9c
        "\x9c"
      when 0x9d
        "\x9d"
      when 0x9e
        "\x9e"
      when 0x9f
        "\x9f"
      when 0xa0
        "\xa0"
      when 0xa1
        "\xa1"
      when 0xa2
        "\xa2"
      when 0xa3
        "\xa3"
      when 0xa4
        "\xa4"
      when 0xa5
        "\xa5"
      when 0xa6
        "\xa6"
      when 0xa7
        "\xa7"
      when 0xa8
        "\xa8"
      when 0xa9
        "\xa9"
      when 0xaa
        "\xaa"
      when 0xab
        "\xab"
      when 0xac
        "\xac"
      when 0xad
        "\xad"
      when 0xae
        "\xae"
      when 0xaf
        "\xaf"
      when 0xb0
        "\xb0"
      when 0xb1
        "\xb1"
      when 0xb2
        "\xb2"
      when 0xb3
        "\xb3"
      when 0xb4
        "\xb4"
      when 0xb5
        "\xb5"
      when 0xb6
        "\xb6"
      when 0xb7
        "\xb7"
      when 0xb8
        "\xb8"
      when 0xb9
        "\xb9"
      when 0xba
        "\xba"
      when 0xbb
        "\xbb"
      when 0xbc
        "\xbc"
      when 0xbd
        "\xbd"
      when 0xbe
        "\xbe"
      when 0xbf
        "\xbf"
      when 0xc0
        "\xc0"
      when 0xc1
        "\xc1"
      when 0xc2
        "\xc2"
      when 0xc3
        "\xc3"
      when 0xc4
        "\xc4"
      when 0xc5
        "\xc5"
      when 0xc6
        "\xc6"
      when 0xc7
        "\xc7"
      when 0xc8
        "\xc8"
      when 0xc9
        "\xc9"
      when 0xca
        "\xca"
      when 0xcb
        "\xcb"
      when 0xcc
        "\xcc"
      when 0xcd
        "\xcd"
      when 0xce
        "\xce"
      when 0xcf
        "\xcf"
      when 0xd0
        "\xd0"
      when 0xd1
        "\xd1"
      when 0xd2
        "\xd2"
      when 0xd3
        "\xd3"
      when 0xd4
        "\xd4"
      when 0xd5
        "\xd5"
      when 0xd6
        "\xd6"
      when 0xd7
        "\xd7"
      when 0xd8
        "\xd8"
      when 0xd9
        "\xd9"
      when 0xda
        "\xda"
      when 0xdb
        "\xdb"
      when 0xdc
        "\xdc"
      when 0xdd
        "\xdd"
      when 0xde
        "\xde"
      when 0xdf
        "\xdf"
      when 0xe0
        "\xe0"
      when 0xe1
        "\xe1"
      when 0xe2
        "\xe2"
      when 0xe3
        "\xe3"
      when 0xe4
        "\xe4"
      when 0xe5
        "\xe5"
      when 0xe6
        "\xe6"
      when 0xe7
        "\xe7"
      when 0xe8
        "\xe8"
      when 0xe9
        "\xe9"
      when 0xea
        "\xea"
      when 0xeb
        "\xeb"
      when 0xec
        "\xec"
      when 0xed
        "\xed"
      when 0xee
        "\xee"
      when 0xef
        "\xef"
      when 0xf0
        "\xf0"
      when 0xf1
        "\xf1"
      when 0xf2
        "\xf2"
      when 0xf3
        "\xf3"
      when 0xf4
        "\xf4"
      when 0xf5
        "\xf5"
      when 0xf6
        "\xf6"
      when 0xf7
        "\xf7"
      when 0xf8
        "\xf8"
      when 0xf9
        "\xf9"
      when 0xfa
        "\xfa"
      when 0xfb
        "\xfb"
      when 0xfc
        "\xfc"
      when 0xfd
        "\xfd"
      when 0xfe
        "\xfe"
      when 0xff
        "\xff"
      else
        puts (uint/0x100).to_s(16)
        puts (uint%0x100).to_s(16)
        u16_to_bytechars(uint/0x100) + u16_to_bytechars(uint%0x100)
    end
  end
end