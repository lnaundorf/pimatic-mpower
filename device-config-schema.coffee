module.exports ={
  title: "pimatic-mpower device config schemas"
  MPowerSwitch:
    title: "MPowerSwitch config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      host:
        description: "Hostname or IP address of the mPower device"
        type: "string"
      portNumber:
        description: "The port number of the mPower device"
        type: "number"
      hideSwitch:
        description: "If the switch should be hidden in the GUI"
        type: "boolean"
        default: false
}
