require "test_helper"

class Net::NTP::OfflineTest < Test::Unit::TestCase
  def ntp_timestamp(unix_time)
    ntp = unix_time.to_r + Net::NTP::NTP_ADJ
    secs = ntp.floor
    [secs, ((ntp - secs) * 2**32).floor].pack("NN")
  end

  def unix_time(ntp_timestamp)
    secs, frac = ntp_timestamp.unpack("NN")
    secs - Net::NTP::NTP_ADJ + frac / 2.0**32
  end

  def reply_packet(originate:, receive:, transmit:)
    (["00011100"] + [2, 6, 0xEC]).pack("B8 C3") +
      [0, 0].pack("NN") +
      [127, 0, 0, 1].pack("C4") +
      ntp_timestamp(receive) +
      originate +
      ntp_timestamp(receive) +
      ntp_timestamp(transmit)
  end

  # Runs a one-shot NTP server on localhost whose clock is +skew+ seconds ahead.
  def with_server(skew: 0)
    server = UDPSocket.new
    server.bind("127.0.0.1", 0)
    requests = Queue.new

    thread = Thread.new do
      request, (_, port, host) = server.recvfrom(1024)
      received_at = Time.now.to_f
      requests << [request, received_at]
      server.send(reply_packet(
        originate: request[40, 8],
        receive: received_at + skew,
        transmit: Time.now.to_f + skew,
      ), 0, host, port)
    end
    thread.report_on_exception = false

    yield server.addr[1], requests
  ensure
    thread&.join(1)
    server&.close
  end

  def test_request_is_48_bytes_client_mode
    with_server do |port, requests|
      Net::NTP.get("127.0.0.1", port, 2)
      request, _ = requests.pop

      assert_equal 48, request.bytesize
      assert_equal 3, request.getbyte(0) & 0x07
    end
  end

  def test_request_transmit_timestamp_matches_local_clock
    with_server do |port, requests|
      Net::NTP.get("127.0.0.1", port, 2)
      request, received_at = requests.pop

      assert_in_delta received_at, unix_time(request[40, 8]), 0.01
    end
  end

  def test_originate_timestamp_precedes_client_receive
    with_server do |port, _|
      response = Net::NTP.get("127.0.0.1", port, 2)

      assert_operator response.originate_timestamp, :<=, response.client_time_receive
      assert_in_delta response.client_time_receive, response.originate_timestamp, 0.01
    end
  end

  def test_offset_measures_server_skew
    with_server(skew: 12.345) do |port, _|
      response = Net::NTP.get("127.0.0.1", port, 2)

      assert_in_delta 12.345, response.offset, 0.01
    end
  end

  def test_offset_uses_client_send_time
    t1 = 1_700_000_000.25
    packet = reply_packet(
      originate: "\0" * 8,
      receive: t1 + 10.5,
      transmit: t1 + 10.75,
    )
    response = Net::NTP::Response.new(packet, t1 + 1.0, t1)

    assert_in_delta 10.125, response.offset, 1e-6
  end
end
