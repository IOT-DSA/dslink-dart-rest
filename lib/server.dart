import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' show ByteData;
import 'dart:io';

import 'package:dslink/utils.dart' show logger;
import 'package:dslink/common.dart' show Path;
import "package:http_multi_server/http_multi_server.dart";
import "package:mustache4dart/mustache4dart.dart";
import "package:mime/mime.dart";

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
      resp
        ..headers
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
        break;
      case 'GET':
        if (sr.subscribe) {
          _subscribe(sr);
          return;
        }
        _get(sr);
        break;
      case 'DELETE':
        _delete(sr);
        break;
      case 'PUT':
        _put(sr);
        break;
      case 'POST':
      case 'PATCH':
        _post(sr);
        break;
      default:
        var resp = new ServerResponse({'error': 'Bad Request'},
            ResponseStatus.badRequest);
        _sendJson(sr, resp);
        break;
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
    _sendError(sr, HttpStatus.NOT_FOUND, 'not found');
  }

  void _sendError(ServerRequest sr, int status, String msg) {
    _addNoCacheHeaders(sr);
    sr.response
      ..statusCode = status
      ..headers.contentType = ContentType.JSON
      ..writeln('{"error": "$msg"}')
      ..close();
  }

  void _sendJson(ServerRequest sr, ServerResponse resp) {
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
      case ResponseStatus.notImplemented:
        sc = HttpStatus.NOT_IMPLEMENTED;
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

  Future<Null> _delete(ServerRequest sr) async {
    var resp = await _manager.deleteRequest(sr);

    _sendJson(sr, resp);
  }

  Future<Null> _post(ServerRequest sr) async {
    var body = await _readJsonData(sr);

    var resp = await _manager.postRequest(sr, body);
    if (resp.status != ResponseStatus.binary) {
      _sendJson(sr, resp);
    } else {
      // Binary
      if (sr.detectType) {
        var res = lookupMimeType('binary', headerBytes: body['data']);
        sr.response.headers.contentType =
            (res != null ? ContentType.parse(res) : ContentType.BINARY);
      } else {
        sr.response.headers.contentType = ContentType.BINARY;
      }

      sr.response..add(body['data'])
            ..close();
    }
  }

  Future<Null> _put(ServerRequest sr) async {
    if (!_manager.isDataHost) {
      _sendError(sr, HttpStatus.NOT_IMPLEMENTED,
          'Data client does not support creating/updating nodes.');
      return;
    }

    var body = await _readJsonData(sr);
    var resp = await _manager.putRequest(sr, body);
    _sendJson(sr, resp);
  }

  Future<Null> _get(ServerRequest sr) async {
    var resp = await _manager.getRequest(sr);

    if (resp.status != ResponseStatus.ok) {
      _sendJson(sr, resp);
      return;
    }

    if (sr.isHtml) {
      _sendHtml(sr, resp);
    } else if (sr.returnValue) {
      _sendValue(sr, resp);
    } else {
      _sendJson(sr, resp);
    }
  }

  void _sendHtml(ServerRequest req, ServerResponse resp) {
    _addNoCacheHeaders(req);
    req.response.headers.contentType = ContentType.HTML;

    var name = resp.body.containsKey(r'$name')
        ? resp.body[r'$name']
        : resp.body[r'?name'];

    if (resp.body[r'$type'] != null) {
      req.response.writeln(Templates.valuePage({
        'name': name,
        'path': resp.body['?path'],
        'editor': resp.body[r'$editor'],
        'binaryType': resp.body[r'$binaryType'],
        'isImage': resp.isImage,
        'isNotImage': !resp.isImage
      }));
    } else {
      var p = new Path(req.path);
      var children = resp.body.keys
          .where((String k) =>
              k.isNotEmpty && !(const ['@', '!', '?', r'$'].contains(k[0])))
          .map((String k) {
        var n = resp.body[k];
        var isVal = n[r'$type'] != null;
        var isAct = n[r'$invokable'] != null && n[r'$invokable'] != 'never';
        return {
          'name': n['?name'],
          'url': n['?url'],
          'path': n['?path'],
          'isValue': isVal,
          'isAction': isAct,
          'isNode': !isVal && !isAct
        };
      }).toList();
      req.response.writeln(Templates.directoryList({
        'name': name,
        'path': resp.body['?path'],
        'url': resp.body['?url'],
        'parent': '${p.parentPath}.html',
        'children': children
      }));
    }

    req.response.close();
  }

  void _sendValue(ServerRequest req, ServerResponse resp) {
    _addNoCacheHeaders(req);
    String etag = resp.body['value_timestamp'];

    req.response.headers
      ..set('ETag', etag)
      ..set('Cache-Control', 'public, max-age=31536000');

    var lastEtag = req.request.headers.value('If-None-Match');
    if (lastEtag == etag) {
      req.response
        ..statusCode = HttpStatus.NOT_MODIFIED
        ..close();
      return;
    }

    var value = resp.body['?value'];
    if (value is Map || value is List) {
      req.response
        ..headers.contentType = ContentType.JSON
        ..write(JSON.encode(value))
        ..close();
      return;
    }

    if (value is! ByteData) {
      req.response
        ..write(value)
        ..close();
      close();
      return;
    }

    var bl = (value as ByteData)
        .buffer
        .asUint8List(value.offsetInBytes, value.lengthInBytes);
    if (req.detectType) {
      var result = lookupMimeType('binary', headerBytes: bl);
      if (result != null) {
        req.response.headers.contentType = ContentType.parse(result);
      } else {
        req.request.headers.contentType =
            resp.isImage ? ContentType.parse('image/jpeg') : ContentType.BINARY;
      }
    } else {
      req.request.headers.contentType =
          resp.isImage ? ContentType.parse('image/jpeg') : ContentType.BINARY;
    }

    req.response
      ..add(bl)
      ..close();
    return;
  }

  Future<Null> _subscribe(ServerRequest req) async {
    if (!(await WebSocketTransformer.isUpgradeRequest(req.request))) {
      _sendError(req, HttpStatus.BAD_REQUEST, 'Expected WebSocket Upgrade');
      return;
    }

    WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(req.request);
    } catch (e) {
      _sendError(req, HttpStatus.INTERNAL_SERVER_ERROR,
          'Failed to upgrade socket: $e');
      return;
    }

    _manager.valueSubscribe(req, socket);
  }

  Future<dynamic> _readJsonData(ServerRequest sr) async {
    String content;
    try {
      content = await UTF8.decodeStream(sr.request);
    } catch (e) {
      logger.warning('Error decoding content. Request: ${sr.request.uri}', e);
      return null;
    }

    try {
      return JSON.decode(content);
    } catch(e) {
      logger.warning('Error JSON Decoding content: $content', e);
      try {
        return Uri.decodeComponent(content);
      } catch (e) {
        logger.warning('Unable to decode content: $content', e);
        return null;
      }
    }
  }

}

abstract class Templates {
  static String _loadTemplateFile(String name) {
    return new File('res/$name.mustache').readAsStringSync();
  }

  static Function valuePage = compile(_loadTemplateFile('value_page'));
  static Function directoryList = compile(_loadTemplateFile('directory_list'));
}
