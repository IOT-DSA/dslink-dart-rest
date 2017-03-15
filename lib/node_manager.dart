import 'dart:io';
import 'dart:async';

abstract class NodeManager {
  bool get isDataHost;

  Future<ServerResponse> getRequest(String path);
}

class ServerRequest {
  String path;
  HttpRequest request;
  HttpResponse get response => request.response;
  String get method => request.method;
  bool isHtml = false;
  bool get childValues => request.uri.queryParameters.containsKey('values');
  bool get base64Value =>
      request.uri.queryParameters.containsKey('value') ||
      request.uri.queryParameters.containsKey('val');

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
  Map<String, String> body;
  ResponseStatus status;

  ServerResponse(this.body, this.status);
}

enum ResponseStatus { badRequest, notFound, error, ok }