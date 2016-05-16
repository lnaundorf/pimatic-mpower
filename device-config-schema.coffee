module.exports ={
  title: "pimatic-mpower device config schemas"
  MPowerSwitch:
    title: "MPowerSwitch config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      host:
        description: "Hostname or IP address of the mPower outlet"
        type: "string"
      portNumber:
        description: "The port number of the mPower outlet"
        type: "number"
        default: 0
      ports:
        description: "The ports for this mPower outlet. An empty array corresponds to all ports"
        type: "array"
        default: []
      additionalAttributes:
        description: "The additional attributes of the mPower outlet"
        type: "array"
        default: []
      hideSwitch:
        description: "If the switch should be hidden in the GUI"
        type: "boolean"
        default: false
}
