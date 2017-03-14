import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";
import "package:dslink/utils.dart";

import "package:http_multi_server/http_multi_server.dart";
import "package:mustache4dart/mustache4dart.dart";
import "package:mime/mime.dart";

import 'package:dslink_rest/rest.dart';

JsonEncoder jsonUglyEncoder = const JsonEncoder();
JsonEncoder jsonEncoder = const JsonEncoder.withIndent("  ");
String toJSON(input) => jsonEncoder.convert(input);

String loadTemplateFile(String name) {
  return new File("res/${name}.mustache").readAsStringSync();
}

String valuePageHtml = loadTemplateFile("value_page");
String directoryListPageHtml = loadTemplateFile("directory_list");
Function valuePageTemplate = compile(valuePageHtml);
Function directoryListPageTemplate = compile(directoryListPageHtml);

launchServer(bool local, int port, String pwd, String user, ServerNode serverNode) async {
  if (user == null || user.isEmpty) {
    user = "dsa";
  }

  handleRequest(HttpRequest request) async {
    if (pwd != null && pwd.isNotEmpty) {
      String expect = BASE64.encode(UTF8.encode("${user}:${pwd}"));
      var found = request.headers.value("Authorization");

      if (found != "Basic ${expect}") {
        request.response.headers.set(
          "WWW-Authenticate", 'Basic realm="DSA Rest Link"'
        );
        request.response.statusCode = 401;
        request.response.close();
        return;
      }
    }

    HttpResponse response = request.response;

    Uri uri = request.uri;
    String method = request.method;
    String ourPath = Uri.decodeComponent(uri.normalizePath().path);

    if (ourPath != "/" && ourPath.endsWith("/")) {
      ourPath = ourPath.substring(0, ourPath.length - 1);
    }

    String hostPath = "${serverNode.path}${ourPath}";
    if (hostPath != "/" && hostPath.endsWith("/")) {
      hostPath = hostPath.substring(0, hostPath.length - 1);
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

    if (ourPath == "/favicon.ico") {
      response.statusCode = HttpStatus.NOT_FOUND;
      response.writeln("Not Found.");
      response.close();
      return;
    }

    if (ourPath == "/index.html") {
      ourPath = "/.html";
    }

    Path p = new Path(hostPath);

    Future applyRemoteValueToMap(String nodePath, Map map, {Uri uri}) async {
      var c = new Completer<ValueUpdate>();
      ReqSubscribeListener listener;
      listener = link.requester.subscribe(nodePath, (ValueUpdate update) {
        if (!c.isCompleted) {
          c.complete(update);
        }

        if (listener != null) {
          listener.cancel();
          listener = null;
        }
      });

      ValueUpdate val = await c.future.timeout(const Duration(seconds: 5), onTimeout: () {
        if (listener != null) {
          listener.cancel();
          listener = null;
        }
        return null;
      });

      if (val != null) {
        var value = val.value;

        if (uri == null || (!uri.queryParameters.containsKey("val") &&
          !uri.queryParameters.containsKey("value"))) {
          if (value is ByteData) {
            value = value.buffer.asUint8List(
              value.offsetInBytes,
              value.lengthInBytes
            );
          }

          if (value is Uint8List) {
            value = BASE64.encode(value);
          }
        }

        map["?value"] = value;
        map["?value_timestamp"] = val.ts;
      }
    }

    Future<Map> getRemoteNodeMap(RemoteNode n, {Uri uri, bool includeChildValues: false}) async {
      if (n == null) {
        return {
          "error": "No Such Node"
        };
      }

      var p = new Path(n.remotePath);
      var map = {
        "?name": p.name,
        "?path": ourPath,
        "?url": request.requestedUri.toString()
      };

      map.addAll(n.configs);
      map.addAll(n.attributes);

      for (String key in n.children.keys) {
        RemoteNode child = n.children[key];

        var x = new Path(child.remotePath);
        var trp = (ourPath == "/" ? "" : ourPath) + "/" + key;
        var m = {
          "?name": x.name,
          "?path": trp,
          "?url": request.requestedUri.replace(
            path: Uri.encodeFull(trp)
          ).toString()
        };

        m.addAll(child.getSimpleMap());

        if (m[r"$type"] is String && includeChildValues == true) {
          await applyRemoteValueToMap(trp, m);
        }

        map[key] = m;
      }

      if (n.configs.containsKey(r"$type")) {
        await applyRemoteValueToMap(ourPath, map, uri: uri);
      }

      return map;
    }

    Map getNodeMap(SimpleNode n, {Uri uri}) {
      if (n == null) {
        return {
          "error": "No Such Node"
        };
      }

      if (n is! RestNode && n is! ServerNode) {
        return {
          "error": "No Such Node"
        };
      }

      var p = new Path(n.path);
      var map = {
        "?name": p.name,
        "?path": "/" + hostPath.split("/").skip(2).join("/")
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

      map.keys
        .where((k) => k.toString().startsWith(r"$$"))
        .toList()
        .forEach(map.remove);

      return map;
    }

    if (method == "GET") {
      if (!serverNode.isDataHost) {
        var isHtml = false;
        if (ourPath.endsWith(".html")) {
          ourPath = ourPath.substring(0, ourPath.length - 5);
          isHtml = true;
        }

        var p = new Path(ourPath);
        if (!p.valid) {
          response.statusCode = HttpStatus.BAD_REQUEST;
          response.writeln(toJSON({
            "error": "Invalid Path: ${p.path}"
          }));
          response.close();
          return;
        }

        var node = await link.requester.getRemoteNode(p.path)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

        if (node == null) {
          response.headers.contentType = ContentType.JSON;
          response.writeln(toJSON({
            "error": "Node not found."
          }));
          response.close();
          return;
        }

        var json = await getRemoteNodeMap(
          node,
          uri: uri,
          includeChildValues: request.uri.queryParameters.containsKey("values")
        );

        var isImage = false;

        if (json[r"$binaryType"] == "image") {
          isImage = true;
        }

        if (json["@filePath"] is String) {
          var mt = lookupMimeType(json["@filePath"]);
          if (mt is String && mt.contains("image")) {
            isImage = true;
          }
        }

        if (isHtml) {
          response.headers.contentType = ContentType.HTML;
          if (json[r"$type"] != null) {
            response.writeln(valuePageTemplate({
              "name": json.containsKey(r"$name") ? json[r"$name"] : json["?name"],
              "path": json["?path"],
              "editor": json[r"$editor"],
              "binaryType": json[r"$binaryType"],
              "isImage": isImage,
              "isNotImage": !isImage
            }));
          } else {
            response.writeln(directoryListPageTemplate({
              "name": json.containsKey(r"$name") ? json[r"$name"] : json["?name"],
              "path": json["?path"],
              "url": json["?url"],
              "parent": p.parentPath + ".html",
              "children": json.keys.where((String x) => x.isNotEmpty && !(
                (const ["@", "!", "?", r"$"]).contains(x[0]))).map((x) {
                var n = json[x];
                return {
                  "name": n["?name"],
                  "url": n["?url"],
                  "path": n["?path"],
                  "isValue": n[r"$type"] != null,
                  "isAction": n[r"$invokable"] != null,
                  "isNode": n[r"$invokable"] == null && n[r"$type"] == null
                };
              }).toList()
            }));
          }
          response.close();
          return;
        }

        if (uri.queryParameters.containsKey("val") || uri.queryParameters.containsKey("value")) {
          String etag = json["?value_timestamp"];

          response.headers.set("ETag", etag);
          response.headers.set("Cache-Control", "public, max-age=31536000");
          json = json["?value"];

          if (request.headers["If-None-Match"] != null && request.headers["If-None-Match"].isNotEmpty) {
            var lastEtag = request.headers.value("If-None-Match");
            if (etag == lastEtag) {
              response.statusCode = HttpStatus.NOT_MODIFIED;
              response.close();
              return;
            }
          }

          if (json is ByteData) {
            var byteList = json.buffer.asUint8List(
              json.offsetInBytes,
              json.lengthInBytes
            );

            if (request.uri.queryParameters.containsKey("detectType")) {
              var result = lookupMimeType("binary", headerBytes: byteList);
              if (result != null) {
                response.headers.contentType = ContentType.parse(result);
              } else {
                response.headers.contentType = isImage ? ContentType.parse("image/jpeg") : ContentType.BINARY;
              }
            } else {
              response.headers.contentType = isImage ? ContentType.parse("image/jpeg") : ContentType.BINARY;
            }

            response.add(byteList);
          } else if (json is Map || json is List) {
            response.headers.contentType = ContentType.JSON;
            response.write(toJSON(json));
          } else {
            response.write(json);
          }
          response.close();
          return;
        } else if (uri.queryParameters.containsKey("watch") ||
          uri.queryParameters.containsKey("subscribe")) {
          if (!(await WebSocketTransformer.isUpgradeRequest(request))) {
            request.response.statusCode = HttpStatus.BAD_REQUEST;
            request.response.writeln("Bad Request: Expected WebSocket Upgrade.");
            request.response.close();
            return;
          }

          var socket = await WebSocketTransformer.upgrade(request);

          ReqSubscribeListener sub;
          Function onValueUpdate;
          onValueUpdate = (ValueUpdate update) {
            if (socket.closeCode != null) {
              return;
            }

            var value = update.value;
            var ts = update.ts;
            var isBinary = value is ByteData || value is Uint8List;

            if (value is ByteData) {
              value = value.buffer.asUint8List(
                value.offsetInBytes,
                value.lengthInBytes
              );
            }

            if (value is Uint8List) {
              value = BASE64.encode(value);
            }

            var msg = {
              "value": value,
              "timestamp": ts
            };

            if (isBinary) {
              msg["bin"] = true;
            }

            socket.add(jsonUglyEncoder.convert(msg));
          };
          sub = link.requester.subscribe(ourPath, onValueUpdate);
          socket.done.then((_) {
            sub.cancel();
          });
          return;
        } else {
          response.headers.contentType = ContentType.JSON;
          response.writeln(toJSON(json));
        }
        response.close();
        return;
      }

      SimpleNode n = link.getNode(hostPath);

      if (!(link.provider as SimpleNodeProvider).hasNode(hostPath)) {
        response.statusCode = HttpStatus.NOT_FOUND;
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON({
          "error": "No Such Node"
        }));
        response.close();
        return;
      }

      var map = getNodeMap(n);

      if (uri.queryParameters.containsKey("val") ||
        uri.queryParameters.containsKey("value")) {
        map = map["?value"];
        if (map is ByteData) {
          response.headers.contentType = ContentType.BINARY;
          response.add(map.buffer.asUint8List(
            map.offsetInBytes,
            map.lengthInBytes
          ));
        } else if (map is Map || map is List) {
          response.headers.contentType = ContentType.JSON;
          response.write(toJSON(map));
        } else {
          response.write(map);
        }
      } else if (uri.queryParameters.containsKey("watch") ||
        uri.queryParameters.containsKey("subscribe")) {
        if (!(await WebSocketTransformer.isUpgradeRequest(request))) {
          request.response.statusCode = HttpStatus.BAD_REQUEST;
          request.response.writeln("Bad Request: Expected WebSocket Upgrade.");
          request.response.close();
          return;
        }

        var socket = await WebSocketTransformer.upgrade(request);

        RespSubscribeListener sub;
        sub = n.subscribe((ValueUpdate update) {
          if (socket.closeCode != null) {
            if (sub != null) {
              sub.cancel();
            }
            return;
          }

          socket.add(jsonUglyEncoder.convert({
            "value": update.value,
            "timestamp": update.ts
          }));
        });

        socket.done.then((_) {
          sub.cancel();
          sub = null;
        });
        return;
      } else {
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON(map));
      }
      response.close();
      return;
    } else if (method == "PUT") {
      if (!serverNode.isDataHost) {
        response.statusCode = HttpStatus.NOT_IMPLEMENTED;
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON({
          "error": "Data Client does not support creating/updating nodes"
        }));
        response.close();
        return;
      }

      var json = await readJSONData(request);
      var mp = p.parent;
      var pathsToCreate = [];
      while (!mp.isRoot) {
        if (!(link.provider as SimpleNodeProvider).hasNode(mp.path)) {
          pathsToCreate.add(mp.path);
        }
        mp = mp.parent;
      }

      if (pathsToCreate.isNotEmpty) {
        pathsToCreate.sort();
        for (var pr in pathsToCreate) {
          link.addNode(pr, {
            r"$is": "rest"
          });
        }
      }

      if ((link.provider as SimpleNodeProvider).hasNode(hostPath)) {
        var node = link[hostPath];
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

      json[r"$is"] = "rest";
      var node = link.addNode(hostPath, json);
      var map = getNodeMap(node);
      map[r"$is"] = "rest";
      response.headers.contentType = ContentType.JSON;
      response.writeln(toJSON(map));
      response.close();
      changed = true;
      return;
    } else if (method == "POST" || method == "PATCH") {
      var json = await readJSONData(request);

      if (!serverNode.isDataHost) {
        if (json is Map && json.keys.length == 1 && json.keys.contains("?value")) {
          var val = json["?value"];
          await link.requester.set(ourPath, val);
          response.headers.contentType = ContentType.JSON;
          response.writeln(
            toJSON(
              await getRemoteNodeMap(
                await link.requester.getRemoteNode(ourPath),
                uri: uri
              )
            )
          );
          response.close();
          return;
        } else if (json is List && uri.path == "/_/values") {
          var values = {};

          for (String key in json.where((x) => x is String)) {
            var result = await link.requester.getNodeValue(key).timeout(const Duration(seconds: 5));
            values[key] = {
              "timestamp": result.ts,
              "value": result.value
            };
          }

          response.headers.contentType = ContentType.JSON;
          response.writeln(toJSON(values));
          response.close();
          return;
        } else if (uri.queryParameters.containsKey("val") ||
          uri.queryParameters.containsKey("value")) {
          await link.requester.set(ourPath, json);
          response.headers.contentType = ContentType.JSON;
          response.writeln(toJSON(
            await getRemoteNodeMap(
              await link.requester.getRemoteNode(ourPath),
              uri: uri
            )));
          response.close();
          return;
        } else if (uri.queryParameters.containsKey("invoke")) {
          var node = await link.requester.getRemoteNode(ourPath)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);

          if (node == null) {
            response.headers.contentType = ContentType.JSON;
            response.writeln(toJSON({
              "error": "Node not found."
            }));
            response.close();
            return;
          }

          if (node.configs[r"$invokable"] == null) {
            response.statusCode = HttpStatus.NOT_IMPLEMENTED;
            response.headers.contentType = ContentType.JSON;
            response.writeln(toJSON({
              "error": "Node is not invokable"
            }));
            response.close();
            return;
          }

          var stream = link.requester.invoke(ourPath, json);
          var updates = <RequesterInvokeUpdate>[];

          StreamSubscription sub;
          sub = stream.listen((RequesterInvokeUpdate update) {
            updates.add(update);
          });

          int timeoutSeconds = 30;
          if (uri.queryParameters.containsKey("timeout")) {
            timeoutSeconds = int.parse(
              uri.queryParameters["timeout"],
              onError: (source) => 0
            );
          }

          if (timeoutSeconds <= 0) {
            timeoutSeconds = 30;
          }

          if (timeoutSeconds > 300) {
            timeoutSeconds = 300;
          }

          var future = sub.asFuture().timeout(
            new Duration(seconds: timeoutSeconds), onTimeout: () {
            sub.cancel();
          });

          await future;

          if (request.uri.queryParameters.containsKey("binary")) {
            for (RequesterInvokeUpdate update in updates) {
              if (update.error != null) {
                var result = {};
                result["error"] = {
                  "message": update.error.msg,
                  "detail": update.error.detail,
                  "path": update.error.path,
                  "phase": update.error.phase
                };
                response.statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
                response.headers.contentType = ContentType.JSON;
                response.writeln(toJSON(result));
                response.close();
                return;
              }

              for (List r in update.rows) {
                for (var x in r) {
                  if (x is ByteData) {
                    response.statusCode = HttpStatus.OK;

                    var byteList = x.buffer.asUint8List(
                      x.offsetInBytes,
                      x.lengthInBytes
                    );
                    if (request.uri.queryParameters.containsKey("detectType")) {
                      var result = lookupMimeType("binary", headerBytes: byteList);
                      if (result != null) {
                        response.headers.contentType = ContentType.parse(result);
                      } else {
                        response.headers.contentType = ContentType.BINARY;
                      }
                    } else {
                      response.headers.contentType = ContentType.BINARY;
                    }

                    response.add(x.buffer.asUint8List(
                      x.offsetInBytes,
                      x.lengthInBytes
                    ));
                    response.close();
                    return;
                  }
                }
              }
            }

            response.statusCode = HttpStatus.BAD_REQUEST;
            response.headers.contentType = ContentType.JSON;
            response.writeln(toJSON({
              "error": "Not a binary invoke."
            }));
            response.close();
            return;
          } else {
            var result = {};

            result.addAll({
              "columns": [],
              "rows": []
            });
            for (RequesterInvokeUpdate update in updates) {
              if (update.error != null) {
                result.clear();
                result["error"] = {
                  "message": update.error.msg,
                  "detail": update.error.detail,
                  "path": update.error.path,
                  "phase": update.error.phase
                };
                response.statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
                break;
              }
              result["columns"].addAll(
                  update.columns.map((x) => x.getData()).toList()
              );
              result["rows"].addAll(update.rows);
            }

            response.headers.contentType = ContentType.JSON;
            response.writeln(toJSON(result));
            response.close();
            return;
          }
        } else if (json is Map
          && json.keys.every(
            (n) {
              var k = n.toString();

              return k.startsWith("@") || k == "?value";
            }
          )) {
          for (var key in json.keys) {
            String p = ourPath;

            if (key != "?value") {
              p += "/${key}";
            }

            await link.requester.set(p, json[key]);
          }

          response.headers.contentType = ContentType.JSON;
          response.writeln(
            toJSON(
              await getRemoteNodeMap(
                await link.requester.getRemoteNode(ourPath),
                uri: uri
              )
            )
          );
          response.close();
          return;
        } else {
          response.statusCode = HttpStatus.NOT_IMPLEMENTED;
          response.headers.contentType = ContentType.JSON;
          response.writeln(toJSON({
            "error": "Data Client does not support updating nodes"
          }));
          response.close();
          return;
        }
      }

      SimpleNode node = link.getNode(hostPath);

      if (!((link.provider as SimpleNodeProvider).hasNode(hostPath))) {
        node = link.addNode(hostPath, json);
        var map = getNodeMap(node);
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON(map));
        response.close();
        changed = true;
        return;
      }

      Map map;
      if (json is Map && json.keys.length == 1 && json.keys.contains("?value")) {
        node.updateValue(json["?value"]);
        map = getNodeMap(node);
      } else if (uri.queryParameters.containsKey("val") ||
          uri.queryParameters.containsKey("value")) {
        node.updateValue(json);
        map = getNodeMap(node);
      } else if (json is Map) {
        map = {};
        map.addAll(json);
        map[r"$is"] = "rest";
        node.load(map);
      } else {
        map = {};
      }
      response.headers.contentType = ContentType.JSON;
      response.writeln(toJSON(map));
      response.close();
      changed = true;
      return;
    } else if (method == "DELETE") {
      if (!serverNode.isDataHost) {
        response.statusCode = HttpStatus.NOT_IMPLEMENTED;
        response.headers.contentType = ContentType.JSON;
        response.writeln(toJSON({
          "error": "Data Clients do not support DELETE"
        }));
        response.close();
      }

      SimpleNode node = link.getNode(hostPath);
      var map = getNodeMap(node);

      if (node is RestNode || node is ServerNode) {
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


}

Future<dynamic> readJSONData(HttpRequest request) async {
  var content = await request.transform(UTF8.decoder).join();

  try {
    return JSON.decode(content);
  } catch (e) {
    try {
      return Uri.decodeComponent(content);
    } catch (x) {
      rethrow;
    }
  }
}

Future<Null> main(List<String> args) async {
  LinkProvider link;
  link = new LinkProvider(args, "REST-", profiles: {
      AddServer.isType: (String path) => new AddServer(path, link),
      ServerNode.isType: (String path) => new ServerNode(path, link),
      CreateValue.isType: (String path) => new CreateValue(path, link),
      CreateNode.isType: (String path) => new CreateNode(path, link),
      RemoveNode.isType: (String path) => new RemoveNode(path, link),
      RestNode.isType: (String path) => new RestNode(path),
    }, defaultNodes: {
      AddServer.pathName: AddServer.def()
    },
    autoInitialize: false, isRequester: true, isResponder: true);

  link.init();
  await link.connect();

}


