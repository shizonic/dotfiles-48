#!/usr/bin/env ruby
require 'json'
require 'io/wait'

# == Panel appearance ==

@size = {
	:width => 1366,
	:height => 24,
	:gap => 12
}
@colours = {
	:transparent => "#00FFFFFF",
	:text => "#FFFFFFFF",
	:block => "#66000000"
}
@fonts = ["Lato", "NanumGothic", "MaterialDesignIcons"]

# == Block variables ==

@app_icons = {
	"Mozilla Firefox" => "\uF239",
	"Mozilla Firefox (Private Browsing)" => "\uF239",
	"Chromium" => "\uF2AF",
	"Sublime Text (UNREGISTERED)" => "\uF173",
	"LibreOffice Writer" => "\uF22C",
	"LibreOffice Calc" => "\uF21B",
	"LibreOffice Impress" => "\uF227"
}
# TODO: styling/format options for desktops block
@desktops = { 
	:show_names => false,
	:current_desktop => "\uF12E",
	:inactive_desktop => "\uF131"
}
@last_music_json = nil

# == Basic/Common stuff ==

# Puts a background with padding behind text
def block(text)
	"#{back_colour :block} #{text} #{back_colour :transparent}"
end

def back_colour(col)
	"%{B#{@colours[col]}}"
end

def text_colour(col)
	"%{F#{@colours[col]}}"
end


# A clickable area
def clickable(command)
	"%{A:#{command}:}#{yield}%{A}"
end

# Gets the name of the current desktop
def current_desktop
	`bspc query -D -d`.chomp
end

# Returns an array of desktop names
def get_desktops
	`bspc query -D`.chomp.split("\n")
end

# == Blocks ==

# Displays battery percentage if a battery is present
def battery
	battery_present = File.file? '/sys/class/power_supply/BAT0/status'
	if battery_present	
		values = Hash.new
		%w(energy_full energy_now status).each do | state |
			File.open("/sys/class/power_supply/BAT0/#{state}", "r") { | f | values[state] = f.gets.chomp }
		end
		pct = ((values["energy_now"].to_f / values["energy_full"].to_f) * 100).round
		icon = ""
		if values["status"] == "Discharging"
			if pct > 90
				icon = "\uF079"
			elsif pct > 80
				icon = "\uF082"
			elsif pct > 70
				icon = "\uF081"
			elsif pct > 60
				icon = "\uF07F"
			elsif pct > 50
				icon = "\uF07E"
			elsif pct > 40
				icon = "\uF07D"
			elsif pct > 30
				icon = "\uF07C"
			elsif pct > 20
				icon = "\uF07B"
			elsif pct > 10
				icon = "\uF07A"
			elsif pct > 5
				icon = "\uF083"
			end
		else
			icon = "\uF084" # TODO: Incremental charging icons
		end
		block "#{icon} #{pct}%"
	else
		nil
	end
end

# The T440p doesn't have a Caps Lock LED so I'm using this instead
def generic_caps_lock
	`xset -q | grep "Caps Lock: *on" 1>/dev/null`;  result=$?.success?
	if result
		block "\uF632"
	end
end

def caps_lock
	status = ""
	File.open("/sys/class/leds/input4::capslock/brightness", "r") { |file| status = file.read.chomp }
	block "\uF632" if status == "1"
end

# Displays icons for each desktop
def desktops
	command = "bspc desktop -f"
	count = 0
	out	= ""
	for desktop in get_desktops
		count += 1
		text = ""
		if count > 1
			text += ' '
		end
		if @desktops[:show_names]
			text += desktop
		else
			if desktop == current_desktop
				text += @desktops[:current_desktop]	
			else
				text += @desktops[:inactive_desktop]
			end
		end
		out += clickable("#{command} #{count}") { text }
	end
	block out
end

# Displays the current song from Google Play Music Desktop Player using Playback API
def music
	if `pidof "Google Play Music Desktop Player"`.length > 0
		file = File.read '/home/mh/.config/Google Play Music Desktop Player/json_store/playback.json'
		data_hash = nil
		if file.length > 2 # sometimes the json responses from GPMDP get malformed, if so use the last
			data_hash = JSON.parse file
			@last_music_json = data_hash
		else
			# puts 'JSON response is too short, using last valid response.'
			data_hash = @last_music_json
		end
		playing = data_hash["playing"]
		artist = data_hash["song"]["artist"]
		title = data_hash["song"]["title"]
		text = ""
		if title == nil
			text = "\uF386 Not playing"
		else
			icon = playing ? "\uF40A" : "\uF3E4"
			text = " #{icon} #{artist} - #{title}"
		end
		block(clickable("google-play-music-desktop-player") { text })
	else
		nil
	end
end

# Displays the SSID of the current WLAN network if connected
def network
	ssid = `iwgetid -r`.chomp
	if ssid.length > 0
		text = "\uF5A9 #{ssid}"
		if ssid.start_with? "IdentifY"
			text = "\uF2DC #{ssid[10..-2]}"
		end
		block(clickable("urxvt -e nmtui") { text })
	else
		nil
	end
end

# Shows the time (12h format)
def time
	block "#{`date +%-I:%M%P`.chomp}"
end

# Displays the title of the currently focused window
def title
	title = `xtitle`.chomp
	if title.length > 0
		display_title = title
		for app, icon in @app_icons
			if title.end_with? app
				if title != app
					cap = " - #{app}".length
					display_title = "#{icon} #{title[0..title.length-cap]}"
				else
					display_title = "#{icon} #{title}"
				end
			end
		end
		block display_title
	else
		nil
	end
end

# Displays volume percentage
def volume
	`amixer get Master | grep "\\[on\\]"`;  result=$?.success?
	if result
		pct = `amixer get Master | grep -o "\[[0-9]*\%\]" | cut -c2-3 | sed 's/%//' | head -n 1`.chomp
		block(clickable("urxvt -e alsamixer") { "\uF580 #{pct}%" })
	else
		nil
	end
end

def vpn
	block "\uF306" if `pidof openvpn`.chomp.length > 0
end

# == Core ==

# The blocks on the left of the bar
@left = Proc.new do
	"#{desktops} #{title}"
end

# The blocks in the centre area of the bar (yes I'm using the British/French spelling just to trigger people)
@centre = Proc.new do
	"#{music}"
end

# The blocks on the right of the bar
@right = Proc.new do
	blocks = [caps_lock, vpn, network, battery, time]
	out = ""
	blocks.each_with_index do | blk, index |
		if blk != nil
			out += blk
			out += " " unless (index + 1) == blocks.length
		end
	end
	out
end

trap("SIGINT") { `bspc config top_padding 0`; exit 0 }
trap("SIGTERM") { `bspc config top_padding 0`; exit 0 }

`bspc config top_padding #{@size[:height]+@size[:gap]}`

# Paratemerise fonts
fonts = ""
@fonts.each { |font| fonts += " -f #{font}" }

#Start lemonbar
begin
	IO.popen("lemonbar -g #{@size[:width]-(@size[:gap]*2)}x#{@size[:height]}+#{@size[:gap]}+#{@size[:gap]} -F '#{@colours[:text]}' -B '#{@colours[:transparent]}'#{fonts}", "r+") do |pipe|
		loop do
			pipe.puts "%{l}#{@left.call}%{c}#{@centre.call}%{r}#{@right.call}"
			`#{pipe.readline}` if pipe.ready?
			sleep 0.25 # Limit updates
		end
	end
rescue Exception => e
	`bspc config top_padding 0`
end
