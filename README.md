# REST Server DSLink

A DSLink for serving and manipulating DSA data using a REST API.

## API

If the REST server has a username/password configured, provide it using basic authentication.
If a password was provided, but not a username, the username is automatically `dsa`.

**Node URL**: `http://host:port/path/to/node`

### Fetch Node

**Method**: GET<br/>

**Query Parameters**

Key | Value | Description
--- | ----- | -----------
values | n/a | Child values are also listed?
value  | n/a | Base64 encode binary data
val    | n/a | Base64 encode binary data

**Example Response**:

```json
{
  "?name": "hello",
  "?path": "/data/hello",
  "$is": "node",
  "$type": "string",
  "?value": "Hello World",
  "?value_timestamp": "2015-08-19T21:50:40.624-04:00"
}
```

### Fetch Multiple Values

**Restrictions**: Client Mode Only<br/>
**Method**: POST<br/>
**Path**: `/_/values`<br/>
**Example Request**:

```json
[
  "/downstream/System/CPU_Usage",
  "/downstream/System/Memory_Usage"
]
```

**Example Response**:

```json
{
  "/downstream/System/CPU_Usage": {
    "timestamp": "MY_TS",
    "value": 15.0
  },
  "/downstream/System/Memory_Usage": {
    "timestamp": "MY_TS",
    "value": 18.0
  }
}
```

### Create/Update Node

#### Behaviors

- If the node already exists, the provided data is merged into the existing node.
- When creating a new node, any parent node that does not exist is created.

**Method**: PUT<br/>
**Example Request**:
```json
{
  "$type": "number",
  "@unit": "%",
  "?value": 30
}
```

**Example Response**:
```json
{
  "?name": "percentage",
  "?path": "/data/percentage",
  "$is": "node",
  "$type": "number",
  "@unit": "%",
  "?value": 30
}
```

### Overwrite Node

**Method**: POST<br/>
**Example Request**:
```json
{
  "$type": "number",
  "@unit": "%",
  "?value": 30
}
```

**Example Response**:
```json
{
  "?name": "percentage",
  "?path": "/data/percentage",
  "$is": "node",
  "$type": "number",
  "@unit": "%",
  "?value": 30
}
```

### Delete Node

**Method**: DELETE<br/>
**Example Response**:
```json
{
  "?name": "percentage",
  "?path": "/data/percentage",
  "$is": "node",
  "$type": "number",
  "@unit": "%",
  "?value": 30
}
```

### WebHook

You can use a node path as a WebHook for services that use this kind of pattern.

Whatever is posted to the URL will become the value of the node.

**URL**: `http://host:port/path/to/node?value`<br/>
**Method**: POST<br/>
**Example Request**:
```json
{
  "my_key": "my_value"
}
```

**Example Response**:
```json
{
  "?name": "hook",
  "?path": "/data/hook",
  "$is": "node",
  "$type": "map",
  "?value": {
    "my_key": "my_value"
  }
}
```
