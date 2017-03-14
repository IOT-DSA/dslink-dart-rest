import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dslink/utils.dart' show logger;
import "package:http_multi_server/http_multi_server.dart";

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
      bool local, int port, String user, String pass) async {

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
      throw new SocketException(
          'Unable to start IPv4 or IPv6 server', port: port);
    }

    var s = new HttpMultiServer(svs);
    var authStr = BASE64.encode(UTF8.encode('$user:$pass'));

    return new Server._(s, local, port, authStr);
  }

  HttpMultiServer _serv;
  String _authStr;

  bool get isLocal => _local;
  bool _local;

  int get port => _port;
  int _port;

  Server._(this._serv, this._local, this._port, this._authStr) {
    _serv.listen(_handleRequests, onError: _listenErr);
  }

  Future<Null> close() async {
    return await _serv?.close(force: true);
  }

  void updateAuth(String user, String pass) {
    _authStr = BASE64.encode(UTF8.encode('$user:$pass'));
  }

  void _handleRequests(HttpRequest req) {

  }

  void _listenErr(error) {
    logger.severe('Error listening for requests', error);
  }

}
