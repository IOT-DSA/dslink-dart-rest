import "dart:async";
import "dart:convert";
import "dart:io";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

import "package:http_multi_server/http_multi_server.dart";

LinkProvider link;

JsonEncoder jsonEncoder = new JsonEncoder.withIndent("  ");

String toJSON(input) => jsonEncoder.convert(input);

launchServer(bool local, int port, SimpleNode node) async {
  List<HttpServer> servers = <HttpServer>[];
  InternetAddress ipv4 = local ? InternetAddress.LOOPBACK_IP_V4 : InternetAddress.ANY_IP_V4;
  InternetAddress ipv6 = local ? InternetAddress.LOOPBACK_IP_V6 : InternetAddress.ANY_IP_V6;

  try {
    servers.add(await HttpServer.bind(ipv4, port));
  } catch (e) {}

  try {
    servers.add(await HttpServer.bind(ipv6, port));
  } catch (e) {}

  HttpMultiServer server = new HttpMultiServer(servers);

  handleRequest(HttpRequest request) async {
    HttpResponse response = request.response;

    Uri uri = request.uri;
    String method = request.method;
    String ourPath = Uri.decodeComponent(uri.normalizePath().path);
    String path = "${node.path}${ourPath}";
    if (path.endsWith("/")) {
      path = path.substring(0, path.length - 1);
    }

    response.headers.set("Cache-Control", "no-cache, no-store, must-revalidate");
    response.headers.set("Pragma", "no-cache");
    response.headers.set("Expires", "0");

    if (method == "OPTIONS") {
      response.headers.set("Access-Control-Allow-Origin", "*");
      response.headers.set("Access-Control-Allow-Methods", "GET, PUT, POST, PATCH, DELETE");
      response.writeln();
      response.close();
      return;
    }

    Path p = new Path(path);

    Map getNodeMap(SimpleNode n) {
      if (n == null) {
        return {
          "error": "No Such Node"
        };
      }

      if (n is! RestNode && n is! ServerNode) {
        return {
          "error": "Not a REST node"
        };
      }

      var p = new Path(n.path);
      var map = {
        "?name": p.name,
        "?path": "/" + path.split("/").skip(2).join("/")
      };

      map.addAll(n.configs);
      map.addAll(n.attributes);

      for (var key in n.children.keys) {
        var child = n.children[key];

        if (child is! RestNode) {
          continue;
        }

        var x = new Path(child.path);
        map[key] = {
          "?name": x.name,
          "?path": "/" + x.path.split("/").skip(2).join("/")
        }..addAll(child.getSimpleMap());
      }

      if (n.lastValueUpdate != null && n.configs.containsKey(r"$type")) {
        map["?value"] = n.lastValueUpdate.value;
        map["?value_timestamp"] = n.lastValueUpdate.ts;
      }

      return map;
    }

    if (method == "GET") {
      SimpleNode n = link.getNode(path);

      if (link.provider.getNode(path) == null) {
        response.statusCode = HttpStatus.NOT_FOUND;
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON({
          "error": "No Such Node"
        }));
        response.close();
        return;
      }

      var map = getNodeMap(n);

      response.headers.contentType = ContentType.JSON;
      response.writeln(toJSON(map));
      response.close();
      return;
    } else if (method == "PUT") {
      var json = await readJSONData(request);
      var mp = p.parent;
      var pathsToCreate = [];
      while (!mp.isRoot) {
        if (link.getNode(mp.path) == null) {
          pathsToCreate.add(mp.path);
        }
        mp = mp.parent;
      }

      if (pathsToCreate.isNotEmpty) {
        pathsToCreate.sort();
        for (var pr in pathsToCreate) {
          link.addNode(pr, {});
        }
      }

      if (link.provider.getNode(path) != null) {
        var node = link.provider.getNode(path);
        Map map;
        if (json.keys.length == 1 && json.keys.contains("?value")) {
          node.updateValue(new ValueUpdate(json["?value"], ts: ValueUpdate.getTs()));
          map = getNodeMap(node);
        } else {
          map = getNodeMap(node);
          map.addAll(json);
          map[r"$is"] = "rest";
          map.keys.where((x) => map[x] == null).toList().forEach(map.remove);
          node.load(map);
        }
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON(map));
        response.close();
        changed = true;
        return;
      }

      var node = link.addNode(path, json);
      var map = getNodeMap(node);
      map[r"$is"] = "rest";
      response.headers.contentType = ContentType.JSON;
      response.writeln(toJSON(map));
      response.close();
      changed = true;
      return;
    } else if (method == "POST" || method == "PATCH") {
      SimpleNode node = link.getNode(path);
      var json = await readJSONData(request);

      if (node == null) {
        node = link.addNode(path, await readJSONData(request));
        var map = getNodeMap(node);
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON(map));
        response.close();
        changed = true;
        return;
      }

      Map map;
      if (json.keys.length == 1 && json.keys.contains("?value")) {
        node.updateValue(json["?value"]);
        map = getNodeMap(node);
      } else {
        map = {};
        map.addAll(json);
        map[r"$is"] = "rest";
        node.load(map);
      }
      response.headers.contentType = ContentType.JSON;
      response.writeln(toJSON(map));
      response.close();
      changed = true;
      return;
    } else if (method == "DELETE") {
      SimpleNode node = link.getNode(path);
      var map = getNodeMap(node);

      if (node == null) {
        response.statusCode = HttpStatus.NOT_FOUND;
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON({
          "error": "No Such Node"
        }));
        response.close();
        return;
      }

      node.remove();
      response.headers.contentType = ContentType.JSON;
      response.writeln(toJSON(map));
      response.close();
      changed = true;
      return;
    }

    response.headers.contentType = ContentType.JSON;
    response.statusCode = HttpStatus.BAD_REQUEST;
    response.writeln(toJSON({
      "error": "Bad Request"
    }));
    response.close();
  }

  server.listen((request) async {
    try {
      await handleRequest(request);
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
      } catch (e) {}
      request.response.writeln("Internal Server Error:");
      request.response.writeln(e);
      request.response.close();
    }
  });

  return server;
}

Future<Map> readJSONData(HttpRequest request) async {
  var content = await request.transform(UTF8.decoder).join();
  return JSON.decode(content);
}

main(List<String> args) async {
  link = new LinkProvider(args, "REST-", profiles: {
    "addServer": (String path) => new SimpleActionNode(path, (Map<String, dynamic> params) async {
      int port = params["port"] is String  ? int.parse(params["port"]) : params["port"];
      bool local = params["local"];
      if (local == null) local = false;

      try {
        var server = await ServerSocket.bind(InternetAddress.ANY_IP_V4, port);
        await server.close();
      } catch (e) {
        return {
          "message": "Failed to bind to port: ${e}"
        };
      }

      link.addNode("/${params["name"]}", {
        r"$is": "server",
        r"$server_port": port,
        r"$server_local": local,
        "Remove": {
          r"$is": "remove",
          r"$invokable": "write"
        }
      });
      changed = true;
      return {
        "message": "Success!"
      };
    }),
    "server": (String path) {
      return new ServerNode(path);
    },
    "rest": (String path) {
      return new RestNode(path);
    },
    "create": (String path) {
      return new SimpleActionNode(path, (Map<String, dynamic> params) {
        var name = params["name"];

        var parent = new Path(path).parent;
        link.addNode("${parent.path}/${name}", {
          r"$is": "rest"
        });
        changed = true;
      });
    },
    "createMetric": (String path) {
      return new SimpleActionNode(path, (Map<String, dynamic> params) {
        var name = params["name"];
        var editor = params["editor"];
        var type = params["type"];

        var parent = new Path(path).parent;
        var node = link.addNode("${parent.path}/${name}", {
          r"$is": "rest",
          r"$type": type,
          r"$writable": "write"
        });

        if (editor != null && editor.isNotEmpty) {
          node.configs[r"$editor"] = editor;
        }

        changed = true;
      });
    },
    "remove": (String path) => new DeleteActionNode.forParent(path, link.provider)
  }, autoInitialize: false);

  var nodes = {
    "Add_Server": {
      r"$name": "Add Server",
      r"$invokable": "write",
      r"$params": [
        {
          "name": "name",
          "type": "string",
          "placeholder": "MyServer"
        },
        {
          "name": "local",
          "type": "bool",
          "description": "Bind to Local Interface",
          "default": false
        },
        {
          "name": "port",
          "type": "int",
          "default": 8020
        }
      ],
      r"$result": "values",
      r"$columns": [
        {
          "name": "message",
          "type": "string"
        }
      ],
      r"$is": "addServer"
    }
  };

  link.init();

  for (var k in nodes.keys) {
    link.addNode("/${k}", nodes[k]);
  }

  link.connect();

  timer = Scheduler.every(Interval.ONE_SECOND, () async {
    if (changed) {
      changed = false;
      await link.saveAsync();
    }
  });
}

bool changed = false;
Timer timer;

class RestNode extends SimpleNode {
  RestNode(String path) : super(path);

  @override
  onCreated() {
    link.addNode("${path}/Create_Node", {
      r"$name": "Create Node",
      r"$is": "create",
      r"$invokable": "write",
      r"$result": "values",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        }
      ]
    });

    link.addNode("${path}/Create_Value", CREATE_VALUE);

    link.addNode("${path}/Remove_Node", {
      r"$name": "Remove Node",
      r"$is": "remove",
      r"$invokable": "write"
    });
  }

  @override
  onSetValue(Object val) {
    if (configs[r"$type"] == "map" && val is String) {
      try {
        var json = JSON.decode(val);
        updateValue(json);
        return true;
      } catch (e) {
        return super.onSetValue(val);
      }
    } else {
      return super.onSetValue(val);
    }
  }

  @override
  updateValue(Object update, {bool force: false}) {
    super.updateValue(update, force: force);
    changed = true;
  }

  @override
  onRemoving() {
    changed = true;
  }
}

final Map<String, dynamic> CREATE_VALUE = {
  r"$name": "Create Value",
  r"$is": "createMetric",
  r"$invokable": "write",
  r"$result": "values",
  r"$params": [
    {
      "name": "name",
      "type": "string"
    },
    {
      "name": "type",
      "type": "enum",
      "editor": buildEnumType([
        "string",
        "number",
        "bool",
        "color",
        "gradient",
        "fill",
        "array",
        "map"
      ])
    },
    {
      "name": "editor",
      "type": "enum",
      "editor": buildEnumType([
        "none",
        "textarea",
        "password",
        "daterange",
        "date"
      ]),
      "default": "none"
    }
  ],
  r"$columns": []
};

class ServerNode extends SimpleNode {
  HttpServer server;

  ServerNode(String path) : super(path);

  @override
  onCreated() async {
    var port = configs[r"$server_port"];
    var local = configs[r"$server_local"];
    if (local == null) local = false;
    server = await launchServer(local, port, this);

    link.addNode("${path}/Create_Node", {
      r"$name": "Create Node",
      r"$is": "create",
      r"$invokable": "write",
      r"$result": "values",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        }
      ]
    });

    link.addNode("${path}/Create_Value", CREATE_VALUE);
  }

  @override
  onRemoving() async {
    if (server != null) {
      await server.close(force: true);
      server = null;
    }
  }
}
