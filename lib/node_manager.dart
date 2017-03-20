import 'dart:io';
import 'dart:async';
import "package:mime/mime.dart";

abstract class NodeManager {
  bool get isDataHost;

  Future<ServerResponse> getRequest(ServerRequest sr);
  Future<ServerResponse> putRequest(ServerRequest sr, Map body);
  Future<ServerResponse> postRequest(ServerRequest sr, dynamic body);
  Future<Null> valueSubscribe(ServerRequest sr, WebSocket socket);
}

class ServerRequest {
  String path;
  HttpRequest request;
  HttpResponse get response => request.response;
  String get method => request.method;
  bool isHtml = false;
  bool get binary => request.uri.queryParameters.containsKey('binary');
  bool get isInvoke => request.uri.queryParameters.containsKey('invoke');
  bool get childValues => request.uri.queryParameters.containsKey('values');
  bool get subscribe => request.uri.queryParameters.containsKey('watch') ||
      request.uri.queryParameters.containsKey('subscribe');
  bool get detectType => request.uri.queryParameters.containsKey('detectType');
  bool get returnValue =>
      request.uri.queryParameters.containsKey('value') ||
      request.uri.queryParameters.containsKey('val');
  int get timeout => int.parse(request.uri.queryParameters['timeout'],
      onError: (_) => null);


  ServerRequest(this.request) {
    path = Uri.decodeComponent(request.uri.normalizePath().path);
    if (path != '/' && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    if (path == '/index.html') {
      path = '/.html';
    }

    if (path.endsWith('.html')) {
      isHtml = true;
      path = path.substring(0, path.length - 5);
    }
  }

}

class ServerResponse {
  Map<String, dynamic> body;
  ResponseStatus status;
  bool get isImage {
    if (body[r'$$binaryType'] == 'image') return true;

    if (body["@filePath"] is String) {
      var mt = lookupMimeType(body["@filePath"]);
      if (mt is String && mt.contains("image")) {
        return true;
      }
    }
    return false;
  }

  ServerResponse(this.body, this.status);
}

enum ResponseStatus { badRequest, notFound, notImplemented, error, ok, binary }