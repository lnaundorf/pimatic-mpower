module.exports = {
  title: "pimatic-mpower config options"
  type: "object"
  properties:
    host:
      description: "Hostname or IP address of the mPower device"
      type: "string"
    interval:
      description: "The interval (in seconds) for mPower updates"
      type: "number"
      default: 10
    username:
      description: "The username for login"
      type: "string"
      default: "ubnt"
    password:
      description: "The password for login"
      type: "string"
      default: "ubnt"
    useWebSockets:
      description: "Whether to use the faster (but unsupported) WebSocket mPower API"
      type: "boolean"
      default: true
}
