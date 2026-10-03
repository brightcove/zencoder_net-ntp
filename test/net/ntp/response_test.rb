require "test_helper"

class Net::NTP::ResponseTest < Test::Unit::TestCase
  def test_root_delay_and_dispersion
    packet = ["00011100", 2, 6, 0xEC, 1, 0x8000, 0, 0x4000].pack("B8 C3 n4") + ("\0" * 36)
    response = Net::NTP::Response.new(packet, 0)

    assert_equal 1.5, response.root_delay
    assert_equal 0.25, response.root_dispersion
  end
end
