# pimatic-mpower

Pimatic plugin to control [Ubiquiti MPower outlets](https://www.ubnt.com/mfi/mpower/).

For using this plugin it is not needed to have the mFi Controller Software running on a separate server, since the plugin directly communicates with the mPower outlet. For obtaining the IP address of the mPower outlet, you can use the "Ubiquiti Device Discovery Tool" which can be downloaded from [https://www.ubnt.com/download/utilities/](https://www.ubnt.com/download/utilities/). To adjust the username, password and other configuration options of the mPower outlet you can login to the web-based administration interface by using the default login credentials ubnt/ubnt.

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


Note that Currently it is not supported to use multiple mPower outlets that have different username/passwords.


## Device configuration

    {
        "id": "mpower-device",
        "name": "mPower",
        "class": "MPowerSwitch",
        "host": "192.168.x.y",
        "ports": [1]
    },

Each of the ports of an mPower outlet must be individually configured by using the ```MPowerSwitch``` device class. The configuration options are as follows:

| Property             | Default  | Type    | Description                                                                                         |
|:---------------------|:---------|:--------|:----------------------------------------------------------------------------------------------------|
| host                 | -        | String  | Hostname or IP address of the mPower outlet                                                         |
| ports                | []       | Array   | The ports of the mPower outlet to use for the device. Empty array for all ports.                    |
| hideSwitch           | false    | Boolean | If the switch should be hidden in the GUI                                                           |
| additionalAttributes | []       | Array   | The additional attributes that should also be collected. See the next section for more information. |

Remember that the port numbers of the mPower outlet start at 1. So the values in the ```ports``` configuration array are exactly what is printed beneath the ports on the mPower outlet. Further, if multiple ports are configured for a single device, the power in Watts is summed up and the state of the device is on iff all ports of the device are turned on, otherwise the state is off.

## Additional Attributes

Beside the on/off-state and the power in Watts there are the following additional attributes that can be collected and displayed by using the ```additionalAttributes``` configuration option. Note that these additional attributes can only be used when the device is configured for a single port of the mPower outlet:

| Name of the property | Physical Unit |
|:---------------------|:--------------|
| current              | Ampere        |
| voltage              | Volt          |
| powerfactor          | -             |
| energy               | -             |

For example a device configuration that uses these attributes can look as follows:

    {
        "id": "mpower-device",
        "name": "mPower",
        "class": "MPowerSwitch",
        "host": "192.168.x.y",
        "ports": [1],
        "additionalAttributes": [
            "current",
            "voltage"
        ]
    },


## web-GUI customization

Especially when some additional attributes are enabled you might want to customize the web-GUI such that some of the additional attributes are hidden.
For this you can use the ```xAttributeOptions``` in the device configuration options as follows:

    {
        "id": "mpower-device",
        "name": "mPower",
        "class": "MPowerSwitch",
        "host": "192.168.x.y",
        "ports": [1],
        "additionalAttributes": [
            "current",
            "voltage",
            "powerfactor",
            "energy"
        ],
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

## Version History

### Version 0.8.X

* Add possibility to use multiple ports for a single device.
* Disable additional attributes per default, use the additionalAttributes configuration option to enable these attributes.
* Automatic reconnect when WebSockets disconnects

### Version 0.8.2

* Update peer dependencies

### Version 0.8.0

* Initial Release
