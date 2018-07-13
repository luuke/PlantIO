dofile("credentials.lua")

-- ***** MQTT *****
-- init mqtt client with logins, keepalive timer 120sec
mqttClient = mqtt.Client("clientid", 120, MQTT.Login, MQTT.Password)
mqttClient:on("connect", function(client) print ("onConnected") end)
mqttClient:on("offline", function(client) print ("MQTT offline") end)
mqttClient:on("message", function(client, topic, data) 
    print(topic .. ":" ) 
    if data ~= nil then
        print(data)
    end
end)

function MQTT_Connect()
    mqttClient:connect(MQTT.Address, MQTT.Port, 0, 
        function(client)
            print("MQTT connected")
            MQTT_Publish(SoilMoisture, "plantio/moisture", 
                function()
                    MQTT_Publish(SoilTemperature,"plantio/temperature", 
                    function()
                        DataSent = 1
                    end
                    )  
                end
                )    
        end,
        function(client, reason)
            print("MQTT connection failed - reason: " .. reason)
            -- Something has gone wrong with connection
            -- No worries, go sleep and try again next time
            Sleep()
        end
        )    
end

function MQTT_Publish(data, topic, callback)
    print("Sending data...")
    mqttClient:publish(topic, data, 0, 0, callback)
end

-- ***** WIFI *****
function WIFI_Setup()
    wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, 
        function()
            print("WIFI connected")
            print("Conneting to MQTT broker...")
            MQTT_Connect()
        end
        )
    wifi.setmode(wifi.STATION)
    wifiConfig = {}
    wifiConfig.ssid = Network.SSID
    wifiConfig.pwd = Network.Password
    wifi.sta.config(wifiConfig)
end

-- ***** Sensors (common) *****
function Sensors_Enable()
    MoistureSensor_Enable()
    TemperatureSensor_Enable()
end

function Sensors_Disable()
    MoistureSensor_Disable()
    TemperatureSensor_Disable()
end

-- ***** Moisture sensor *****
function MoistureSensor_Enable()
    gpio.write(outMoistureSensor, gpio.HIGH) 
end

function MoistureSensor_Disable()
    gpio.write(outMoistureSensor, gpio.LOW) 
end

function MoistureSensor_Read()
    return adc.read(0)
end

-- ***** Temperature sensor *****
TemperatureSensorAddress = "28:87:19:43:98:24:00:61"
function TemperatureSensor_Enable()
    -- So far this is covered together with moisture sensor
end

function TemperatureSensor_Disable()
    -- So far this is covered together with moisture sensor
end

function TemperatureSensor_Setup()
    ds18b20.setting({TemperatureSensorAddress}, 12)
end

function TemperatureSensor_Read()
    SoilTemperatureReady = 0
    ds18b20.read(
        TemperatureSensor_ReadCallback,
        {TemperatureSensorAddress}
        );
end

function TemperatureSensor_ReadCallback(ind,rom,res,temp,tdec,par)
    SoilTemperatureReady = 1
    Sensors_Disable()
    SoilTemperature = temp .. "." .. tdec
    print("Soil temperature: " .. SoilTemperature)
end

-- ***** Water pump *****
function WaterPump_On()
    gpio.write(outWaterPump, gpio.HIGH) 
end

function WaterPump_Off()
    gpio.write(outWaterPump, gpio.LOW)
end

function WaterPump_WaterThePlant()
    print("Watering...")
    
    wateringTime = 5000 -- [ms]
    WaterPump_On()
    waterTimer = tmr.create()
    waterTimer:alarm(wateringTime, tmr.ALARM_SINGLE, 
        function()    
            print("Watering done")
            WaterPump_Off()
            WateringDone = 1
        end
        )
end

-- ***** Utils *****
function Delay(ms)
    startTick = tmr.now()
    repeat
        -- Do nothing, this is just delay
    until ( (tmr.now() - startTick) > ( ms * 1000 ) )
end

function Sleep()
    print("Going to sleep for " .. (AppInterval / 1000000) .. " seconds")
    gpio.write(outLED, gpio.HIGH) 
    node.dsleep(AppInterval) 
end
    
-- ***** GPIO *****
outLED = 4
outTemperatureSensor = 5
outMoistureSensor = 7
outWaterPump = 8
gpio.mode(outLED, gpio.OUTPUT)
gpio.mode(outMoistureSensor, gpio.OUTPUT)
gpio.mode(outWaterPump, gpio.OUTPUT)
ds18b20.setup(outTemperatureSensor)

-- ***** App *****
AppInterval = 300000000 -- 5 minutes
gpio.write(outLED, gpio.LOW) 

print("----- PlantIO -----")
Sensors_Enable()
Delay(500) -- delay for sensor to stabilize
SoilMoisture = MoistureSensor_Read()
print("Soil moisture: " .. SoilMoisture)

TemperatureSensor_Setup()
Delay(500) -- delay for sensor to stabilize
TemperatureSensor_Read() -- trigger reading wait for callback
-- Sensors are disabled in temperature sensor read callback

if SoilMoisture > 700 then 
    WateringDone = 0
    WaterPump_WaterThePlant()
else
    WateringDone = 1
end

DataSent = 0

sensorsReadWaitTimer = tmr.create()
sensorsReadWaitTimer:alarm(1000, tmr.ALARM_AUTO, 
    function()
        if WateringDone == 1 and SoilTemperatureReady == 1 then
            sensorsReadWaitTimer:stop()
            print("Opening WIFI connection...")
            WIFI_Setup()
        else
            -- Just wait
            print(".")
        end
    end
    )

dataSentWaitTimer = tmr.create()
dataSentWaitTimer:alarm(1000, tmr.ALARM_AUTO, 
    function()
        if DataSent == 1 then
            dataSentWaitTimer:stop()
            Sleep()
        else
            -- Just wait
            print(":")
        end
    end
    )