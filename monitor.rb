#!/usr/bin/env ruby

require 'bundler/setup'
require 'rrd'
require 'yaml'
require 'telegram/bot'
require 'pi_piper'

config = YAML.load_file('config.yml')

rrd_file = config['rrd_file']
ts_file = config['ts_file']

rrd = RRD::Base.new(rrd_file)

begin
  include PiPiper

  vcc_pin = PiPiper::Pin.new(:pin => config['vcc_out_pin'], :direction => :out)
  vcc_pin.on
  sleep 0.2

  pin = PiPiper::Pin.new(:pin => config['input_pin'], :direction => :in, :pull => :up)
  value = pin.read
  value = ( 1 - value ).abs
  rrd.update Time.now, value
rescue Exception => e
  puts e.to_s
ensure
  vcc_pin.off
end

if ( File.exists?( ts_file ) )
  last_message_ts = File.open( ts_file, &:readline )
  exit if ( Time.now.to_i - last_message_ts.to_i < 12*60*60)
end

begin
  data = rrd.fetch(:max, { start: Time.now - 20.minutes, end: Time.now - 5.minutes })
  data.shift # first item is the headers

  unwatered = true
  data.each { |item|
    unwatered = false unless ( item[1] == 0 )
  }

  if ( unwatered )
    File.open( ts_file, 'w' ) do |file|
      file.puts( Time.now.to_i.to_s )
    end
  
    Telegram::Bot::Client.run( config['tg_token'] ) do |bot|
      bot.api.send_message(chat_id: config['tg_chat_id'], text: config['tg_message'] )
    end
  end
rescue StandardError => e
  puts e.to_s
end
