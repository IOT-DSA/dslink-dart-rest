# REST Server DSLink

A DSLink for serving and manipulating DSA data using a REST API.

## API

**Node URL**: `http://host:port/path/to/node`

### Fetch Node

**Method**: GET<br/>
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

## Create/Update Node

### Behaviors

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

## Overwrite Node

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

## Delete Node

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
