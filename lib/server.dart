import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dslink/utils.dart' show logger;
import "package:http_multi_server/http_multi_server.dart";

import 'node_manager.dart';

class Server {
  static Future<bool> checkPort(int port) async {
    if (port == null || port <= 0 || port > 65535) return false;

    try {
      var s = await ServerSocket.bind(InternetAddress.ANY_IP_V4, port);
      await s.close();
    } catch (e) {
      logger.warning('Check Port failed port: $port', e);
      return false;
    }
    return true;
  }

  static Future<Server> bind(
      bool local, int port, String user, String pass, NodeManager man) async {
    if (port == null || port <= 0 || port > 65535) {
      throw new SocketException('Invalid port number', port: port);
    }

    var svs = <HttpServer>[];

    var ipv4 =
        local ? InternetAddress.LOOPBACK_IP_V4 : InternetAddress.ANY_IP_V4;
    var ipv6 =
        local ? InternetAddress.LOOPBACK_IP_V6 : InternetAddress.ANY_IP_V6;

    var failed = 0;
    try {
      svs.add(await HttpServer.bind(ipv4, port));
    } catch (e) {
      logger.warning('Unable to start IPv4 server', e);
      failed += 1;
    }

    try {
      svs.add(await HttpServer.bind(ipv6, port));
    } catch (e) {
      logger.warning('Unable to start IPv6 server', e);
      failed += 1;
    }

    if (failed >= 2) {
      throw new SocketException('Unable to start IPv4 or IPv6 server',
          port: port);
    }

    var s = new HttpMultiServer(svs);
    String authStr;

    if (pass != null && pass.isNotEmpty)
      authStr = BASE64.encode(UTF8.encode('$user:$pass'));

    return new Server._(s, local, port, authStr, man);
  }

  HttpMultiServer _serv;
  NodeManager _manager;
  String _authStr;
  bool get _authEnabled => _authStr != null;

  bool get isLocal => _local;
  bool _local;

  int get port => _port;
  int _port;

  Server._(this._serv, this._local, this._port, this._authStr, this._manager) {
    _serv.listen(_handleRequests, onError: _listenErr);
  }

  Future<Null> close() async {
    return await _serv?.close(force: true);
  }

  void updateAuth(String user, String pass) {
    if (pass == null || pass.isEmpty)
      _authStr = null;
    else
      _authStr = BASE64.encode(UTF8.encode('$user:$pass'));
  }

  bool _checkAuth(HttpRequest req) {
    var authHead = req.headers.value(HttpHeaders.AUTHORIZATION);

    if (authHead != 'Basic ${_authStr}') {
      var resp = req.response;
      resp..headers
          .set(HttpHeaders.WWW_AUTHENTICATE, 'Basic realm="DSA Rest Link"')
        ..statusCode = HttpStatus.UNAUTHORIZED
        ..close();
      return false;
    }

    return true;
  }

  void _handleRequests(HttpRequest req) {
    if (_authEnabled) {
      if (!_checkAuth(req)) return;
    }

    var sr = new ServerRequest(req);

    if (sr.path == '/favicon.ico') {
      _notFound(sr);
      return;
    }

    switch (sr.method) {
      case 'OPTIONS':
        _options(sr);
        return;
      case 'GET':
        _get(sr);
        return;
    }
  }

  void _listenErr(error) {
    logger.severe('Error listening for requests', error);
  }

  // Add Headers to prevent caching responses.
  void _addNoCacheHeaders(ServerRequest sr) {
    sr.response.headers
      ..set(HttpHeaders.CACHE_CONTROL, "no-cache, no-store, must-revalidate")
      ..set(HttpHeaders.PRAGMA, 'no-cache')
      ..set(HttpHeaders.EXPIRES, '0');
  }

  // 404 Page not found
  void _notFound(ServerRequest sr) {
    _addNoCacheHeaders(sr);
    sr.response
      ..statusCode = HttpStatus.NOT_FOUND
      ..headers.contentType = ContentType.JSON
      ..writeln('{"error":"not found"}')
      ..close();
  }

  void _sendJsonError(ServerRequest sr, ServerResponse resp) {
    int sc;
    switch (resp.status) {
      case ResponseStatus.badRequest:
        sc = HttpStatus.BAD_REQUEST;
        break;
      case ResponseStatus.notFound:
        sc = HttpStatus.NOT_FOUND;
        break;
      case ResponseStatus.ok:
        sc = HttpStatus.OK;
        break;
      case ResponseStatus.error:
      default:
        sc = HttpStatus.INTERNAL_SERVER_ERROR;
        break;
    }

    var body = JSON.encode(resp.body);
    _addNoCacheHeaders(sr);
    sr.response
        ..statusCode = sc
        ..headers.contentType = ContentType.JSON
        ..writeln(body)
        ..close();
  }

  // Respond to Options requests.
  void _options(ServerRequest sr) {
    sr.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, PUT, POST, PATCH, DELETE');
    sr.response
      ..writeln()
      ..close();
  }

  Future<Null> _get(ServerRequest sr) async {
    var resp = await _manager.getRequest(sr.path);

    if (resp.status != ResponseStatus.ok) {
      _sendJsonError(sr, resp);
      return;
    }
  }
}
