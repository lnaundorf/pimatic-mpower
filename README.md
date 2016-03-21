# pimatic-mpower

Pimatic plugin to control [Ubiquiti MPower devices](https://www.ubnt.com/mfi/mpower/).

For using this plugin it is not needed to have the mFi Controller Software running on a separate server, since the plugin directly communicates with the mPower device. For obtaining the IP address of the mPower device, you can use the "Ubiquiti Device Discovery Tool" which can be downloaded from [https://www.ubnt.com/download/utilities/](https://www.ubnt.com/download/utilities/). To adjust the username, password and other configuration options of the mPower device you can login to the web-based administration interface of the device by using the default login credentials ubnt/ubnt.

## Plugin configuration

    {
        "plugin": "mpower"
    }

The plugin has the following configuration properties:

| Property          | Default  | Type    | Description                                 |
|:------------------|:---------|:--------|:--------------------------------------------|
| username          | ubnt     | String  | The username for login                      |
| password          | ubnt     | String  | The password for login                      |
| intervall         | 5000     | Number  | The update intervall in milliseconds        |


Note that Currently it is not supported to use multiple mPower devices that have different username/passwords.


## Device configuration

    {
        "id": "mpower-device",
        "name": "mPower",
        "class": "MPowerSwitch",
        "host": "192.168.x.y",
        "portNumber": 1
    },

Each of the ports of an mPower device must be individually configured by using the ```MPowerSwitch``` device class. The configuration options are as follows:

| Property          | Default  | Type    | Description                                 |
|:------------------|:---------|:--------|:--------------------------------------------|
| host              | -        | String  | Hostname or IP address of the mPower device |
| portNumber        | -        | Number  | The port number of the mPower Device        |
| hideSwitch        | false    | Boolean | If the switch should be hidden in the GUI   |

Remember that the port numbers of the mPower devices start at 1. So the value for ```portNumber``` is exactly what is printed beneath the port on the mPower device.

## web-GUI customization

For further customization which elements should be shown in the pimatic web-GUI you can use the ```xAttributeOptions``` in the device configuration options as follows:

    {
        "id": "mpower-device",
        "name": "mPower",
        "class": "MPowerSwitch",
        "host": "192.168.x.y",
        "portNumber": 1,
        "xAttributeOptions": [
            {
                "name": "state",
                "hidden": true
            },
            {
                "name": "current",
                "hidden": true
            },
            {
                "name": "voltage",
                "hidden": true
            },
            {
                "name": "powerfactor",
                "hidden": true
            },
            {
                "name": "energy",
                "hidden": true
            }
        ]
    },

## Further information

This plugin uses the more sophisticated WebSocket API of the mPower devices instead of the published HTTP API from [here](https://community.ubnt.com/t5/mFi/mPower-mFi-Switch-and-mFi-In-Wall-Outlet-HTTP-API/td-p/1076449). The WebSocket API is not documented but is easier to implement and switching the state of a port by using WebSockets is much faster than by using the HTTP API. Hence, it is not guaranteed that this plugin works with future firmwares of the mPower devices since the WebSockets API may change at any time.