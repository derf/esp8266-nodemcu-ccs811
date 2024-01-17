local ccs811 = {}
local device_address = 0x5a

ccs811.mode = nil

function ccs811.start()
	local ret = true
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		ret = false
	end
	i2c.write(0, 0xf4)
	i2c.stop(0)
	return ret
end

function ccs811.setMode(mode)
	local ret = true
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		ret = false
	end
	i2c.write(0, 0x01, bit.lshift(mode, 4))
	i2c.stop(0)
	ccs811.mode = mode
	return ret
end

function ccs811.setEnv(humi, temp)
	local ret = true
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		ret = false
	end
	i2c.write(0, 0x05, math.floor(humi) * 2, 0, (math.floor(temp) + 25) * 2, 0)
	i2c.stop(0)
	return ret
end

function ccs811.read()
	local ret = true
	if ccs811.mode == nil then
		ccs811.setMode(1)
		return
	end
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.TRANSMITTER) then
		ret = false
	end
	i2c.write(0, 0x02)
	i2c.start(0)
	if not i2c.address(0, device_address, i2c.RECEIVER) then
		ret = false
	end
	local data = i2c.read(0, 6)
	i2c.stop(0)

	ccs811.eco2 = bit.lshift(string.byte(data, 1), 8) + string.byte(data, 2)
	ccs811.tvoc = bit.lshift(string.byte(data, 3), 8) + string.byte(data, 4)
	ccs811.status = string.byte(data, 5)
	ccs811.err_id = string.byte(data, 6)

	return ret
end

return ccs811
