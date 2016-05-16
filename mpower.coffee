# #Plugin template

# This is an plugin template and mini tutorial for creating pimatic plugins. It will explain the 
# basics of how the plugin system works and how a plugin should look like.

# ##The plugin code

# Your plugin must export a single function, that takes one argument and returns a instance of
# your plugin class. The parameter is an envirement object containing all pimatic related functions
# and classes. See the [startup.coffee](http://sweetpi.de/pimatic/docs/startup.html) for details.
module.exports = (env) ->

  # ###require modules included in pimatic
  # To require modules that are included in pimatic use `env.require`. For available packages take 
  # a look at the dependencies section in pimatics package.json

  # Require the  bluebird promise library
  Promise = env.require 'bluebird'

  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'

  # Require the request-promise library for the login to the mpower device
  request = require 'request-promise'

  # Require the W3CWebsocket library for the communication to the mpower device
  WebSocket = require('websocket').w3cwebsocket

  # ###MyPlugin class
  # Create a class that extends the Plugin class and implements the following functions:
  class MPowerPlugin extends env.plugins.Plugin

    # ####init()
    # The `init` function is called by the framework to ask your plugin to initialise.
    #  
    # #####params:
    #  * `app` is the [express] instance the framework is using.
    #  * `framework` the framework itself
    #  * `config` the properties the user specified as config for your plugin in the `plugins` 
    #     section of the config.json file 
    #     
    # 
    init: (app, @framework, @config) =>
      @username = @config.username
      @password = @config.password
      @intervall = @config.intervall
      # Retry intervall for webSocket reconnect is 5000ms
      @wsRetryInterval = 5000
      # Check every 20 seconds whether a websocket is still connected
      @wsCheckConnectedInterval = 20000

      # holds the data of the physical mPower switch devices
      @physicalDevicesData = {}

      # Maps a deviceId to the corresponding ports of a switch device
      @deviceMapping = {}

      # Maps ports to the corresponding deviceIds
      @portMapping = {}


      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("MPowerSwitch", {
        configDef: deviceConfigDef.MPowerSwitch,
        createCallback: (config, lastState) => new MPowerSwitch(config, @, lastState)
      })


    addDevice: (deviceDescription) ->
      env.logger.debug("Add device: #{deviceDescription.host} --> #{deviceDescription.ports}")
      newDevice = false
      if not @physicalDevicesData[deviceDescription.host]?
        newDevice = true

        @physicalDevicesData[deviceDescription.host] = {
          ports: {}
          cookie: null
          ws: null
        }

      # Add the device to the deviceMapping
      @deviceMapping[deviceDescription.id] = {
        device: deviceDescription.device
        host: deviceDescription.host
        ports: deviceDescription.ports
      }

      # Add the device to the portMapping
      if not @portMapping[deviceDescription.host]?
        @portMapping[deviceDescription.host] = {}

      portsToAdd = deviceDescription.ports

      if not portsToAdd.length
        # The port '0' corresponds to all ports of a device
        portsToAdd = [0]

      for port in portsToAdd
        if not @portMapping[deviceDescription.host][port]?
          env.logger.debug("Add physical device port #{deviceDescription.host}: #{port}")
          @portMapping[deviceDescription.host][port] = []

        @portMapping[deviceDescription.host][port].push(deviceDescription.id)

      # TODO: Restore last state for multiple ports?
      #if deviceDescription.lastState?
      #  @_restoreLastState(deviceDescription.host, port.portNumber, port.lastState)
      #  #env.logger.debug("Data: #{JSON.stringify(@physicalDevicesData[port.host].ports[port.portNumber].data, null, 2)}")

      if newDevice
        @_initSwitchDevice(deviceDescription.host)

    _restoreLastState: (host, portNumber, lastState) =>
      #env.logger.debug("Restore last state of #{host}, port #{portNumber}: #{JSON.stringify(lastState, null, 2)}")

      port = @physicalDevicesData[host].ports[portNumber]

      for property, state of lastState
        # Only use data if it is not older than 1 hour
        if Date.now() - state.time <= 1 * 3600 * 1000
          port.data[property] = state.value
          port.device.emit(property, state.value)


    createWebSocket: (host, data) =>
      env.logger.debug("Creating WebSocket for host #{host}")
      ws = new WebSocket("ws://#{host}:7681/?c=#{data.cookie}", "mfi-protocol")
      ws.onopen = () =>
        env.logger.debug("WebSocket opened for #{host}.")
        ws.send(JSON.stringify({
          time: 10
        }))
        if data.checkConnectedId
          env.logger.debug("Clear Interval for host #{host}.")
          clearInterval data.checkConnectedId
        data.checkConnectedId = setInterval( =>
          now = Date.now()
          env.logger.debug("Check WebSocket for #{host}. Now: #{now}, lastReceivedMessage: #{data.lastMessageReceived}.")
          # If no message was received in the last interval close the WebSocket
          if data.ws and data.ws.readyState == 1 and (not data.lastMessageReceived or now - data.lastMessageReceived >= @wsCheckConnectedInterval)
            env.logger.info("No message received in the last #{@wsCheckConnectedInterval} ms. Reconnect webSocket for #{host}.")
            data.ws.onclose = null
            data.ws.close()
            data.ws = null
            @_initSwitchDevice(host)
        , @wsCheckConnectedInterval)
        env.logger.debug("#{data.checkConnectedId}")

      ws.onmessage = (msg) => @_updateSensorData(host, msg)
      ws.onclose = () =>
        env.logger.info("WS closed for #{host}. Trying to reconnect.")
        # reconnect the WebSocket
        @_initSwitchDevice(host)
      ws.onerror = () -> env.logger.warn("Error for webSocket for #{host}.")

      data.ws = ws

    getData: (deviceId, attribute) ->
      new Promise( (resolve) => resolve(@_getUpdatedDeviceData(deviceId, [attribute])))

    changeStateTo: (deviceId, state) ->
      new Promise((resolve) =>
        deviceDescription = @deviceMapping[deviceId]

        host = deviceDescription.host
        ws = @physicalDevicesData[host].ws

        if not ws?
          env.logger.error("No WebSocket available for #{host}.")
        else
          portsToIterate = deviceDescription.ports

          if not portsToIterate.length
            portsToIterate = Object.keys(@physicalDevicesData[host].ports)

          for portNumber in portsToIterate
            update = {
              sensors: [
                {
                  output: if state then 1 else 0
                  port: portNumber
                }
              ]
            }
            env.logger.debug("Sending WebSocket message to #{host}: #{JSON.stringify(update, null, 2)}")
            ws.send(JSON.stringify(update))

            portDevice = @physicalDevicesData[host].ports[portNumber]

            if portDevice?
              portDevice.data.output = if state then 1 else 0

          # TODO: Emit new data for other devices that use the same port
          deviceDescription.device.emit("state", state)

        resolve()
      ).catch( (error) =>
        env.logger.error("Error while updating the state to #{state}: #{error}")
        # create new cookie and try again to login
        @_initSwitchDevice(host)
        Promise.reject()
      )

    _generateSessionId: () ->
      # Generates a random 32 digit session ID
      text = ""
      possible = "0123456789"

      for i in [1..32]
        text += possible.charAt Math.floor(Math.random() * possible.length)

      return text

    _initSwitchDevice: (host) ->
      data = @physicalDevicesData[host]
      return new Promise( (resolve, reject) =>
        data.cookie = @_generateSessionId()
        env.logger.debug("Login, host: #{host}, cookie: #{data.cookie}")
        request.post(
          url: "http://#{host}/login.cgi"
          form:
            username: @username
            password: @password
          headers:
            Cookie: "AIROS_SESSIONID=#{data.cookie}"
          followRedirect: false
          simple: false
        ).then( =>
          env.logger.debug("Login successful for host #{host}.")
          @createWebSocket(host, data)

          resolve()
        ).catch( (error) =>
          env.logger.error("Error while logging in for #{host}: #{error}")
          setTimeout (=> @_initSwitchDevice(host)), @wsRetryInterval
          #reject()
          resolve()
        )
      )

    _updateSensorData: (host, webSocketMessage) ->
      data = @physicalDevicesData[host]
      jsonData = null
      try
        jsonData = JSON.parse(webSocketMessage.data)
      catch error
        env.logger.warn("Error while parsing WebSocket message for #{host}: #{error}")
        env.logger.warn(webSocketMessage.data)
        return
      #env.logger.debug("Update sensor data for #{host}, message: #{JSON.stringify(jsonData, null, 2)}")

      for portData in jsonData.sensors
        if not data.ports[portData.port]?
          data.ports[portData.port] = {
            data: {}
            lastUpdated: null
          }

        savedPortData = data.ports[portData.port]

        # Update the data
        savedPortData.data = portData

        now = Date.now()
        data.lastMessageReceived = now
        lastUpdated = savedPortData.lastUpdated
        if not lastUpdated? or now - lastUpdated >= @intervall
          savedPortData.lastUpdated = now

          # emit the new data to the framework
          responsibleDeviceIds = @_getResponsibleDeviceIds(host, portData.port)

          for devId in responsibleDeviceIds
            env.logger.debug("Update device: #{devId}")
            updatedData = @_getUpdatedDeviceData(devId)
            device = @deviceMapping[devId]?.device

            # Emit the updated data
            for key, value of updatedData
              #env.logger.debug("Emit for device #{device.id}: #{key} -> #{value}")
              device.emit(key, value)

    _getResponsibleDeviceIds: (host, portNumber) ->
      responsibleDeviceIds = []
      # Search for all devices that use this port
      if @portMapping[host]?
        #env.logger.debug("Portmapping for host #{host}: #{JSON.stringify(@portMapping[host], null, 2)}")
        deviceIdsAllPorts = @portMapping[host][0] || []
        deviceIdsPort = @portMapping[host][portNumber] || []

        responsibleDeviceIds = deviceIdsAllPorts.concat(deviceIdsPort)
        env.logger.debug("Responsible devices for #{host}, port #{portNumber}: #{responsibleDeviceIds}")
        return responsibleDeviceIds
      else
        return []


    _getUpdatedDeviceData: (deviceId, properties) ->
          deviceDescription = @deviceMapping[deviceId]
          if deviceDescription?
            hostData = @physicalDevicesData[deviceDescription.host]

            if hostData?
              propertiesToSum = ["output", "power", "current"]
              isSinglePort = deviceDescription.ports.length is 1 or Object.keys(hostData.ports).length <= 1

              if isSinglePort
                propertiesToSum.push("voltage")
                propertiesToSum.push("powerfactor")
                propertiesToSum.push("energy")

              computedData = {}

              numberOfPorts = 0

              for portNumber, val of hostData.ports
                #env.logger.debug("Ports for device #{deviceId}: #{JSON.stringify(deviceDescription.ports, null, 2)}, val: #{JSON.stringify(val.data, null, 2)}")
                if not deviceDescription.ports.length or parseInt(portNumber, 10) in deviceDescription.ports
                  hostDataPort = val.data
                  if hostDataPort?
                    numberOfPorts++
                    #env.logger.debug("hostData for port #{portNumber}: #{JSON.stringify(hostDataPort, null, 2)}")
                    for propName in propertiesToSum
                      if not properties? or propName in properties
                        valBase = computedData[propName] || 0
                        valToSum = hostDataPort[propName] || 0
                        computedData[propName] = valBase + valToSum

              # The result state should be 1 if all of the part states are 1
              if "output" of computedData
                #env.logger.debug("Computed State: #{computedData.output}, number of ports: #{numberOfPorts}.")
                computedData.state = Math.floor(computedData.output / numberOfPorts)

              #env.logger.debug("Updated device data: #{JSON.stringify(computedData, null, 2)}")

              if properties? and properties.length is 1
                # If just one property-value is request return just the value
                return computedData[properties[0]] || 0
              else
                # return the computed property object
                return computedData

  class MPowerSwitch extends env.devices.PowerSwitch

    # The additional attributes which can also be enabled by using
    # the "additionalAttributes" device configuration option
    allowedAdditionalAttributes:
      current:
        description: "The current in amps"
        type: "number"
        unit: "A"
      voltage:
        description: "The current voltage"
        type: "number"
        unit: "V"
      powerfactor:
        description: "The power factor"
        type: "number"
      energy:
        description: "The energy"
        type: "number"
      state:
        description: "The state of the Power switch"
        type: "boolean"
        labels: ['on', 'off']


    getTemplate: -> Promise.resolve(@template)

    getState: -> @plugin.getData(@id, "state")

    getPower: -> @plugin.getData(@id, "power")

    changeStateTo: (state) -> @plugin.changeStateTo(@id, state)

    constructor: (@config, @plugin, lastState) ->
      @name = @config.name
      @id = @config.id

      ports = {} # The empty array corresponds to all ports of a device
      if @config.ports.length > 0
        ports = @config.ports
      else if @config.portNumber != 0
        ports = [@config.portNumber]

      @template = if @config.hideSwitch then "device" else "switch"

      # Configure the available attributes of the device

      # "power" is the default attributes
      @attributes =
        power:
          description: "The current power usage in watts"
          type: "number"
          unit: "W"

      # Also show the 'state' if the switch should not be hidden
      if not @config.hideSwitch
        @attributes['state'] = @allowedAdditionalAttributes['state']

      # Create getters for the additional attributes
      for attributeName in @config.additionalAttributes
        if attributeName of @allowedAdditionalAttributes
          env.logger.debug("Adding additional attribute: #{attributeName}")
          @_createGetter attributeName, ( => @plugin.getData(@id, attributeName))
          @attributes[attributeName] = @allowedAdditionalAttributes[attributeName]
        else
          env.logger.error("Ignore unknown additional attribute: #{attributeName}")

      @plugin.addDevice {
        id: @id
        host: @config.host
        ports: ports
        device: @
        lastState: lastState
      }
      super()


  # ###Finally
  # Create a instance of my plugin
  # and return it to the framework.
  return new MPowerPlugin
