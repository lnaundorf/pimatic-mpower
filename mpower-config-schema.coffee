module.exports = {
  title: "pimatic-mpower config options"
  type: "object"
  properties:
    username:
      description: "The username for login"
      type: "string"
      default: "ubnt"
    password:
      description: "The password for login"
      type: "string"
      default: "ubnt"
    intervall:
      description: "The update intervall in milliseconds"
      type: "number"
      default: 5000
}
