# ESP8266 Lua/NodeMCU module for CCS811 VOC sensors

[esp8266-nodemcu-ccS811](https://finalrewind.org/projects/esp8266-nodemcu-ccs811/)
provides an ESP8266 NodeMCU Lua module (`ccs811.lua`) as well as MQTT /
HomeAssistant / InfluxDB gateway application example (`init.lua`) for
**CCS811** volatile organic compounds (VOC) sensors connected via I²C.  The
application example assumes that an **HDC1080** sensor for temperature and
humidity compensation is available as well.

## Dependencies

ccs811.lua has been tested with Lua 5.1 on NodeMCU firmware 3.0.1 (Release
202112300746, float build). It requires the following modules.

* bit
* i2c

Most practical applications (such as the example in init.lua) also need the
following modules.

* gpio
* hdc1080
* http
* mqtt
* node
* tmr
* wifi

## Setup

Connect the CCS811 sensor (or CCS811/HDC1080 combo board) to your
ESP8266/NodeMCU board as follows.

* CCS811 GND → ESP8266/NodeMCU GND
* CCS811 VCC → ESP8266/NodeMCU 3V3
* CCS811 SDA → NodeMCU D1 (ESP8266 GPIO5)
* CCS811 SCL → NodeMCU D2 (ESP8266 GPIO4)

If you use different pins for SCL and SDA, you need to adjust the i2c.setup
call in the examples provided in this repository to reflect those changes. Keep
in mind that some ESP8266 pins must have well-defined logic levels at boot time
and may therefore be unsuitable for CCS811 connection.

## Usage

Copy **ccs811.lua** to your NodeMCU board and set it up as follows.

```lua
ccs811 = require("ccs811")
i2c.setup(0, 1, 2, i2c.SLOW)
ccs811.start()
-- optionally, if HDC1080 is available:
hdc1080.setup()

-- can be called with up to 1 Hz
function some_timer_callback()
	if ccs811.read() then
		-- ccs811.eco2   : equivalent CO₂ (estimated from tvoc, unreliable) [ppm]
		-- ccs811.tvoc   : Total Volatile Organic Compounds [ppb]
		-- ccs811.status : Status Register; see manual
		-- ccs811.error  : Error Register; see manual. error == 0 indicates that everything is alright.
		-- optionally, if HDC1080 is available:
		local t, h = hdc1080.read()
		ccs811.setEnv(h, t)
	end
end
```

The sensor performs an air quality measurement every second.

## Application Example

**init.lua** is an example application with HomeAssistant integration.
To use it, you need to create a **config.lua** file with WiFI and MQTT settings:

```lua
station_cfg = {ssid = "...", pwd = "..."}
mqtt_host = "..."
```

Optionally, it can also publish readings to InfluxDB.
To do so, configure URL and attribute:

```lua
influx_url = "..."
influx_attr = "..."
```

Readings will be published as `ccs811[influx_attr] eco2_ppm=%d,tvoc_ppb=%d,status=%d,error=%d`.
Unless `influx_attr = ''`, it must start with a comma, e.g. `influx_attr = ',device=' .. device_id`.

## Flashing

This repository contains a NodeMCU build that provides the required modules.
You can flash it using e.g. esptool:

```bash
esptool write_flash 0x00000 firmware/nodemcu-release-12-modules-2024-01-18-19-25-08-float.bin
```

This is required just once; changes to Lua files generally do not mandate
flashing a new NodeMCU image.

After flashing, the firmware will need a few seconds to initialize the
filesystem. You can then upload the Python code, e.g. using nodemcu-uploader:

```bash
ext/nodemcu-uploader/nodemcu-uploader.py upload *.lua
```

Afterwards, you can check whether everything works using the serial connection,
e.g.

```bash
pyserial-miniterm --dtr 0 --rts 0 /dev/ttyUSB0 115200
```

You may need to adjust the `/dev/tty` device name.

## Images

![](https://finalrewind.org/projects/esp8266-nodemcu-ccs811/media/hass.png)
