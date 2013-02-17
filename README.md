RabbitMQ HTTP Publishing Exchange
=================================

Adds a HTTP based publishing end-point to RabbitMQ that aims to provide better
performance than publishing messages via the Management plugin API.

Each x-http exchange listens on a specific port for incoming HTTP POST requests
and relays them to objects in RabbitMQ that are bound to it (Exchanges, Queues).

Declaring an x-http exchange
----------------------------

Declare a new exchange specifying the type as x-http and with the following arguments:

    Key       Type    Optional? Description
    ---------------------------------------------------------------------------------------------
    port      number  No        The port to listen for HTTP requests on
    ip        string  yes       IP address to listen on; default is 0.0.0.0
    username  string  yes       A username that when specified requires HTTP Basic Authentication
    password  string  yes       The password required for HTTP Basic Authentication

The ip string, if supplied, must be a numeric IPv4 address string of the form X.Y.Z.W. If ip is missing, the exchange will listen at the specified port on all interfaces.

Deleting an x-http exchange
---------------------------
Deleting an x-http exchange causes the system to stop listening for HTTP requests on the exchange's configured port.

Request Format
--------------
The x-http exchange can processes POST requests specific to the VHost it was declared on and has a simple API:

- URL Format: http://host:port/routing-key
- POST content-types: application/json or application/x-www-form-urlencoded.
- POST Payload:
    - application/json
        - A JSON document the following nodes:
            - body
            - properties
                - app_id
                - content_encoding
                - content_type
                - correlation_id
                - expires
                - headers
                - message_id
                - priority
                - reply-to
                - timestamp
                - type
                - user_id
    - application/x-www-form-urlencoded
        - POST query string with the following key/value pairs
            - app_id
            - body
            - content_encoding
            - content_type
            - correlation_id
            - expires
            - headers
            - message_id
            - priority
            - reply-to
            - timestamp
            - type
            - user_id
