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

LinkProvider link;

launchServer(bool local, int port, String pwd, String user, ServerNode serverNode) async {

  handleRequest(HttpRequest request) async {
    HttpResponse response = request.response;

    Uri uri = request.uri;
    String method = request.method;
    String ourPath = Uri.decodeComponent(uri.normalizePath().path);

    // TODO in NodeManager
    String hostPath = "${serverNode.path}${ourPath}";

    Path p = new Path(hostPath);

    Future<Map> getRemoteNodeMap(RemoteNode n, {Uri uri, bool includeChildValues: false}) async {

    }

    Map getNodeMap(SimpleNode n, {Uri uri}) {

    }

    if (method == "GET") {
     // Done
    } else if (method == "PUT") {
    // Done
    } else if (method == "POST" || method == "PATCH") {
      var json = await readJSONData(request);

      if (!serverNode.isDataHost) {
        if (json is Map && json.keys.length == 1 && json.keys.contains("?value")) {
        // DONE
        } else if (json is List && uri.path == "/_/values") {
        // DONE
        } else if (uri.queryParameters.containsKey("val") ||
            uri.queryParameters.containsKey("value")) {
          // DONE
        } else if (uri.queryParameters.containsKey("invoke")) {
          var node = await link.requester.getRemoteNode(ourPath)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);

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
          // END of Invoke
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

      // IS Data host below

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


