publishing_mqtt = false
publishing_http = false

watchdog = tmr.create()
push_timer = tmr.create()
chip_id = string.format("%06X", node.chipid())
device_id = "esp8266_" .. chip_id
mqtt_prefix = "sensor/" .. device_id
mqttclient = mqtt.Client(device_id, 120)

dofile("config.lua")

print("CCS811 " .. chip_id)

ledpin = 4
gpio.mode(ledpin, gpio.OUTPUT)
gpio.write(ledpin, 0)

ccs811 = require("ccs811")
i2c.setup(0, 1, 2, i2c.SLOW)

function log_restart()
	print("Network error " .. wifi.sta.status())
end

function setup_client()
	print("Connected")
	gpio.write(ledpin, 1)
	publishing_mqtt = true
	mqttclient:publish(mqtt_prefix .. "/state", "online", 0, 1, function(client)
		publishing_mqtt = false
		hdc1080.setup()
		ccs811.start()
		push_timer:start()
	end)
end

function connect_mqtt()
	print("IP address: " .. wifi.sta.getip())
	print("Connecting to MQTT " .. mqtt_host)
	mqttclient:on("connect", hass_register)
	mqttclient:on("offline", log_restart)
	mqttclient:lwt(mqtt_prefix .. "/state", "offline", 0, 1)
	mqttclient:connect(mqtt_host)
end

function connect_wifi()
	print("WiFi MAC: " .. wifi.sta.getmac())
	print("Connecting to ESSID " .. station_cfg.ssid)
	wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, connect_mqtt)
	wifi.eventmon.register(wifi.eventmon.STA_DHCP_TIMEOUT, log_restart)
	wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, log_restart)
	wifi.setmode(wifi.STATION)
	wifi.sta.config(station_cfg)
	wifi.sta.connect()
end

function push_data()
	local t, h = hdc1080.read()
	local json_str = string.format('{"temperature_degc": %.1f, "humidity_relpercent": %.1f', t, h)
	local influx_str = string.format("temperature_degc=%.1f,humidity_relpercent=%.1f", t, h)
	if ccs811.read() then
		json_str = json_str .. string.format(', "eco2_ppm": %d, "tvoc_ppb": %d, "status": "0x%02x", "error": "0x%02x"', ccs811.eco2, ccs811.tvoc, ccs811.status, ccs811.err_id)
		influx_str = influx_str .. string.format(',eco2_ppm=%d,tvoc_ppb=%d,status=%d,error=%d', ccs811.eco2, ccs811.tvoc, ccs811.status, ccs811.err_id)
		ccs811.setEnv(h, t)
	else
		json_str = json_str .. ', "status": "Initializing", "error": "0x00"'
	end
	json_str = json_str .. string.format(', "rssi_dbm": %d}', wifi.sta.getrssi())
	if not publishing_mqtt then
		publishing_mqtt = true
		watchdog:start(true)
		gpio.write(ledpin, 0)
		mqttclient:publish(mqtt_prefix .. "/data", json_str, 0, 0, function(client)
			publishing_mqtt = false
			if influx_url and influx_attr then
				publish_influx(influx_str)
			else
				gpio.write(ledpin, 1)
				collectgarbage()
			end
		end)
	end
end

function publish_influx(payload)
	if not publishing_http then
		publishing_http = true
		http.post(influx_url, influx_header, "ccs811" .. influx_attr .. " " .. payload, function(code, data)
			publishing_http = false
			gpio.write(ledpin, 1)
			collectgarbage()
		end)
	end
end

function hass_register()
	local hass_device = string.format('{"connections":[["mac","%s"]],"identifiers":["%s"],"model":"ESP8266 + HDC1080 + CCS811","name":"CCS811 %s","manufacturer":"derf"}', wifi.sta.getmac(), device_id, chip_id)
	local hass_entity_base = string.format('"device":%s,"state_topic":"%s/data","expire_after":120', hass_device, mqtt_prefix)
	local hass_temp = string.format('{%s,"name":"Temperature","object_id":"%s_temp","unique_id":"%s_temp","device_class":"temperature","unit_of_measurement":"°c","value_template":"{{value_json.temperature_degc}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)
	local hass_humi = string.format('{%s,"name":"Humidity","object_id":"%s_humidity","unique_id":"%s_humidity","device_class":"humidity","unit_of_measurement":"%%","value_template":"{{value_json.humidity_relpercent}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)
	--local hass_eco2 = string.format('{%s,"name":"eCO₂","object_id":"%s_eco2","unique_id":"%s_eco2","device_class":"carbon_dioxide","unit_of_measurement":"ppm","value_template":"{{value_json.eco2_ppm}}"}', hass_entity_base, device_id, device_id)
	local hass_voc = string.format('{%s,"name":"VOC","object_id":"%s_voc","unique_id":"%s_voc","unit_of_measurement":"ppb","icon":"mdi:air-filter","value_template":"{{value_json.tvoc_ppb}}"}', hass_entity_base, device_id, device_id)
	local hass_status = string.format('{%s,"name":"Status","object_id":"%s_status","unique_id":"%s_status","icon":"mdi:information","value_template":"{{value_json.status}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)
	local hass_error = string.format('{%s,"name":"Error","object_id":"%s_error","unique_id":"%s_error","icon":"mdi:alert-circle","value_template":"{{value_json.error}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)
	local hass_rssi = string.format('{%s,"name":"RSSI","object_id":"%s_rssi","unique_id":"%s_rssi","device_class":"signal_strength","unit_of_measurement":"dBm","value_template":"{{value_json.rssi_dbm}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)

	mqttclient:publish("homeassistant/sensor/" .. device_id .. "/temperature/config", hass_temp, 0, 1, function(client)
		mqttclient:publish("homeassistant/sensor/" .. device_id .. "/humidity/config", hass_humi, 0, 1, function(client)
			--mqttclient:publish("homeassistant/sensor/" .. device_id .. "/eco2/config", hass_eco2, 0, 1, function(client)
				mqttclient:publish("homeassistant/sensor/" .. device_id .. "/tvoc/config", hass_voc, 0, 1, function(client)
					mqttclient:publish("homeassistant/sensor/" .. device_id .. "/status/config", hass_status, 0, 1, function(client)
						mqttclient:publish("homeassistant/sensor/" .. device_id .. "/error/config", hass_error, 0, 1, function(client)
							mqttclient:publish("homeassistant/sensor/" .. device_id .. "/rssi/config", hass_rssi, 0, 1, function(client)
								collectgarbage()
								setup_client()
							end)
						end)
					end)
				end)
			--end)
		end)
	end)
end

watchdog:register(180 * 1000, tmr.ALARM_SEMI, node.restart)
push_timer:register(10 * 1000, tmr.ALARM_AUTO, push_data)
watchdog:start()

connect_wifi()
