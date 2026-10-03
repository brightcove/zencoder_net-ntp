require "test_helper"

class Net::NTP::ResponseTest < Test::Unit::TestCase
  def test_precision_is_signed
    packet = ["00011100", 2, 6, 0xEC].pack("B8 C3") + ("\0" * 44)

    assert_equal(-20, Net::NTP::Response.new(packet, 0).precision)
  end
end
