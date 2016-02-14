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

  request = require 'request-promise'

  W3CWebSocket = require('websocket').w3cwebsocket

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

      @switchDevices = {}

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("MPowerSwitch", {
        configDef: deviceConfigDef.MPowerSwitch,
        createCallback: (config, lastState) => new MPowerSwitch(config, @, lastState)
      })


    addPort: (port) ->
      env.logger.debug("Add port: #{port.host} --> #{port.portNumber}")
      newDevice = false
      dev = @switchDevices[port.host]
      if not dev
        newDevice = true
        newHost = {
          ports: {}
          cookie: null
          ws: null
        }

        @switchDevices[port.host] = newHost

      @switchDevices[port.host].ports[port.portNumber] = {
        data: {}
        device: port.device
      }

      if port.lastState?
        @_restoreLastState(port.host, port.portNumber, port.lastState)
        #env.logger.debug("Data: #{JSON.stringify(@switchDevices[port.host].ports[port.portNumber].data, null, 2)}")

      if newDevice
        @_initSwitchDevice(port.host)

    _restoreLastState: (host, portNumber, lastState) =>
      #env.logger.debug("Restore last state of #{host}, port #{portNumber}: #{JSON.stringify(lastState, null, 2)}")

      port = @switchDevices[host].ports[portNumber]

      for property, state of lastState
        # Only use data if it is not older than 1 hour
        if Date.now() - state.time <= 1 * 3600 * 1000
          port.data[property] = state.value
          port.device.emit(property, state.value)


    createWebSocket: (host, data) =>
      env.logger.debug("Creating WebSocket for host #{host}")
      ws = new W3CWebSocket("ws://#{host}:7681/?c=#{data.cookie}", "mfi-protocol")
      ws.onopen = () ->
        ws.send(JSON.stringify({
          time: 10
        }))
      ws.onmessage = (msg) => @_updateSensorData(host, msg)
      ws.onclose = () -> env.logger.debug("WS closed for #{host}.")

      data.ws = ws

    getData: (host, portNumber, attribute) ->
      new Promise( (resolve) =>
        if @switchDevices[host]?
          if @switchDevices[host][portNumber]?
            if @switchDevices[host][portNumber].data[attribute]?
              resolve(@switchDevices[host][portNumber].data[attribute])

        resolve(0)
      )

    changeStateTo: (host, portNumber, state) ->
      new Promise((resolve, reject) =>
        ws = @switchDevices[host].ws

        if not ws?
          env.logger.error("No WebSocket available.")
          reject()

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

        portDevice = @switchDevices[host][portNumber]

        if portDevice?
          portDevice.data.output = if state then 1 else 0
          portDevice.device.emit("state", state)

        resolve()
      ).catch( (error) =>
        env.logger.error("Error while updating the state to #{state}: #{error}")
        # create new cookie and try again to login
        @_initSwitchDevice(host)
        reject()
      )

    _generateSessionId: () ->
      # Generates a random 32 digit session ID
      text = ""
      possible = "0123456789"

      for i in [1..32]
        text += possible.charAt Math.floor(Math.random() * possible.length)

      return text

    _initSwitchDevice: (host) ->
      data = @switchDevices[host]
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
          reject()
        )
      )

    _updateSensorData: (host, webSocketMessage) ->
      data = @switchDevices[host]
      jsonData = JSON.parse(webSocketMessage.data)
      #env.logger.debug("Update sensor data for #{host}, message: #{JSON.stringify(jsonData, null, 2)}")

      for portData in jsonData.sensors
        if data.ports[portData.port]?
          data.ports[portData.port].data = portData

          # emit the new data to the framework
          device = data.ports[portData.port].device

          if device?
            # The "output" attribute should be mapped to the "state" attribute
            device.emit("state", portData.output)
            device.emit("power", portData.power)
            device.emit("current", portData.current)
            device.emit("voltage", portData.voltage)
            device.emit("powerfactor", portData.powerfactor)
            device.emit("energy", portData.energy)

  class MPowerSwitch extends env.devices.PowerSwitch
  
    constructor: (@config, @plugin, lastState) ->
      @name = @config.name
      @id = @config.id
      @host = @config.host
      @portNumber = @config.portNumber
      @template = if @config.hideSwitch then "device" else "switch"

      @plugin.addPort {
        host: @host
        portNumber: @portNumber
        device: @
        lastState: lastState
      }
      super()

    attributes:
      state:
        description: "The state of the Power switch"
        type: "boolean"
        labels: ['on', 'off']
      power:
        description: "The current power usage in watts"
        type: "number"
        unit: "W"
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

    getTemplate: -> Promise.resolve(@template)

    getState: -> @plugin.getData(@host, @portNumber, "output")

    getPower: -> @plugin.getData(@host, @portNumber, "power")

    getCurrent: -> @plugin.getData(@host, @portNumber, "current")

    getVoltage: -> @plugin.getData(@host, @portNumber, "voltage")

    getPowerfactor: -> @plugin.getData(@host, @portNumber, "powerfactor")

    getEnergy: -> @plugin.getData(@host, @portNumber, "energy")

    changeStateTo: (state) -> @plugin.changeStateTo(@host, @portNumber, state)


  # ###Finally
  # Create a instance of my plugin
  # and return it to the framework.
  return new MPowerPlugin
