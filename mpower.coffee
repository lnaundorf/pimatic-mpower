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
      @useWebSockets = @config.useWebSockets

      @switchDevices = {}

      @interval = @config.interval

      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("MPowerSwitch", {
        configDef: deviceConfigDef.MPowerSwitch,
        createCallback: (config) => new MPowerSwitch(config, @)
      })

      setInterval(( => @update()
      ), @interval * 1000)

    addPort: (port) ->
      env.logger.debug("Add port: #{port.host} --> #{port.portNumber}")
      dev = @switchDevices[port.host]
      if not dev
        cookie = @_generateSessionId()
        newHost = {
          ports: {}
          cookie: cookie
          authenticated: false
        }

        @switchDevices[port.host] = newHost

      @switchDevices[port.host].ports[port.portNumber] = {
        data: {}
        device: port.device
      }

    createWebSocket: (host, cookie) ->
      env.logger.debug("Creating WebSocket for host #{host}")
      ws = new W3CWebSocket("ws://#{host}:7681/?c=#{cookie}", "mfi-protocol")
      ws.onopen = () ->
        ws.send(JSON.stringify({
          time: 10
        }))
      ws.onmessage = (msg) -> env.logger.debug("WS message for #{host}: #{JSON.stringify(JSON.parse(msg.data), null, 2)}")
      ws.onclose = () -> env.logger.debug("WS closed for #{host}.")

      return ws

    getData: (host, portNumber, attribute) ->
      new Promise( (resolve) =>
        if @switchDevices[host]?
          if @switchDevices[host][portNumber]?
            if @switchDevices[host][portNumber]["data"][attribute]?
              resolve(@switchDevices[host][portNumber]["data"][attribute])

        resolve(0)
      )

    _getChangeStateFunction: (host, portNumber, state) ->
      if @useWebSockets
        return new Promise ( (resolve) =>
          ws = @switchDevices[host].ws
          update = {
            sensors: [
              {
                output: if state then 1 else 0
                port: portNumber
              }
            ]
          }
          env.logger.debug("Sending WebSeocket message to #{host}: #{JSON.stringify(update, null, 2)}")
          ws.send(JSON.stringify(update))
          resolve()
        )
      else
        return request.post(
          url: "http://#{host}/sensors/#{portNumber}"
          form:
            output: if state then "1" else "0"
          headers:
            Cookie: @switchDevices[host].cookie
          followRedirect: false
          simple: false
        )

    changeStateTo: (host, portNumber, state) ->
      new Promise((resolve) =>
        Promise.resolve(
          @_getChangeStateFunction(host, portNumber, state)
        ).then( =>
          portDevice = @switchDevices[host][portNumber]

          if portDevice?
            portDevice["data"].output = if state then 1 else 0
            portDevice["device"].emit("state", state)

          resolve()
        ).catch( (error) =>
          env.logger.error("Error while updating the state to #{state}: #{error}")
          @switchDevices[host].cookie = null
        )
      )


    update: () -> Promise.all(@_updateHost(host, data) for host, data of @switchDevices)

    _updateHost: (host, data) ->
      env.logger.debug("Updating host: #{host}")
      new Promise( (resolve) =>
        @_getSessionId(host, data)
          .then(@_login(host, data))
          .then(@_updateSensorData(host, data))
          .catch( (error) =>
            data.cookie = null
            env.logger.error("Error while updating host: #{error}")
          )
        resolve()
      )

    
    _getSessionId: (host, data) ->
      new Promise( =>
        env.logger.debug("_getSessionId Host: #{host}")
        if not data.cookie?
          data.cookie = @_generateSessionId()
          data.authenticated = false
          env.logger.debug("Generated cookie for #{host}: #{data.cookie}")
        else
          env.logger.debug("Cookie for host #{host} already generated: #{data.cookie}")
      )

    _generateSessionId: () ->
      # Generates a random 32 digit session ID
      text = ""
      possible = "0123456789"

      for i in [1..32]
        text += possible.charAt Math.floor(Math.random() * possible.length)

      return text

    _login: (host, data) ->
      new Promise( (resolve) =>
        if not data.authenticated
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
            data.authenticated = true
            if @useWebSockets
              data.ws = @createWebSocket(host, data.cookie)

            resolve()
          ).catch( (error) =>
            env.logger.error("Error while logging in: #{error}")
          )
        else
          env.logger.debug("Already authenticated for host #{host}, skipping login.")
          resolve()
      )

    _updateSensorData: (host, data) ->
      env.logger.debug("Update sensor data, host: #{host}, cookie: #{data.cookie}")
      request.get(
        url: "http://#{host}/sensors"
        headers:
          Cookie: "AIROS_SESSIONID=#{data.cookie}"
        followRedirect: false
        simple: false
      )
      .then(JSON.parse)
      .then( (jsonData) =>
        #env.logger.debug("Got sensor data for #{host}: #{JSON.stringify(jsonData, null, 2)}")

        for portData in jsonData.sensors
          #env.logger.debug("Port data: #{JSON.stringify(portData, null, 2)}")
          if data.ports[portData.port]?
            data.ports[portData.port]["data"] = portData

            # emit the new data to the framework
            device = data.ports[portData.port]["device"]

            if device?
              # The "output" attribute should be mapped to the "state" attribute
              device.emit("state", portData.output)
              device.emit("power", portData.power)
              device.emit("enabled", portData.enabled)
              device.emit("current", portData.current)
              device.emit("voltage", portData.voltage)
              device.emit("powerfactor", portData.powerfactor)
              device.emit("relay", portData.relay)
              device.emit("lock", portData.lock)
              device.emit("thismonth", portData.thismonth)
              device.emit("lastmonth", portData.lastmonth)
      )
      .catch( (error) =>
        env.logger.error("Error while updating sensor data: #{error}")
      )

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
      enabled:
        description: "TODO: enabled"
        type: "boolean"
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
      relay:
        description: "TODO: relay"
        type: "boolean"
      lock:
        description: "TODO: lock"
        type: "boolean"
      thismonth:
        description: "The total power usage this month in kWh"
        type: "number"
        unit: "kWh"
      lastmonth:
        description: "The total power usage last month in kWh"
        type: "number"
        unit: "kWh"

    getTemplate: -> Promise.resolve(@template)

    getState: -> @plugin.getData(@host, @portNumber, "output")

    getPower: -> @plugin.getData(@host, @portNumber, "power")

    getEnabled: -> @plugin.getData(@host, @portNumber, "enabled")

    getCurrent: -> @plugin.getData(@host, @portNumber, "current")

    getVoltage: -> @plugin.getData(@host, @portNumber, "voltage")

    getPowerfactor: -> @plugin.getData(@host, @portNumber, "powerfactor")

    getRelay: -> @plugin.getData(@host, @portNumber, "relay")

    getLock: -> @plugin.getData(@host, @portNumber, "lock")

    getThismonth: -> @plugin.getData(@host, @portNumber, "thismonth")

    getLastmonth: -> @plugin.getData(@host, @portNumber, "lastmonth")

    changeStateTo: (state) -> @plugin.changeStateTo(@host, @portNumber, state)


  # ###Finally
  # Create a instance of my plugin
  # and return it to the framework.
  return new MPowerPlugin
