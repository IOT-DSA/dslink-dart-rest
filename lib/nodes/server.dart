import 'dart:async';
import 'dart:io' show WebSocket;
import "dart:typed_data";
import 'dart:convert' show BASE64, JSON;

import 'package:dslink/dslink.dart';
import 'package:dslink/utils.dart' show logger;

import 'create_value.dart';
import 'remove.dart';
import 'rest.dart';

import '../server.dart';
import '../node_manager.dart';

class AddServer extends SimpleNode {
  static const String isType = 'addServer';
  static const String pathName = 'Add_Server';

  static const String _name = 'name';
  static const String _local = 'local';
  static const String _port = 'port';
  static const String _type = 'type';
  static const String _user = 'username';
  static const String _pass = 'password';
  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> def() => {
        r'$is': isType,
        r"$name": "Add Server",
        r"$invokable": "write",
        r"$params": [
          {"name": _name, "type": "string", "placeholder": "MyServer"},
          {
            "name": _local,
            "type": "bool",
            "description": "Bind to Local Interface",
            "default": false
          },
          {"name": _port, "type": "number", 'editor': 'int', "default": 8020},
          {
            "name": _type,
            "type": "enum[${ServerNode.DataHost},${ServerNode.DataClient}]",
            "default": "Data Host",
            "description": "Data Type"
          },
          {"name": _user, "type": "string", "placeholder": "Optional Username"},
          {
            "name": _pass,
            "type": "string",
            "editor": "password",
            "placeholder": "Optional Password"
          }
        ],
        r"$result": "values",
        r"$columns": [
          {"name": _success, "type": "bool", 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ],
      };

  final LinkProvider link;

  AddServer(String path, this.link) : super(path);

  @override
  Future<Map<String, dynamic>> onInvoke(Map<String, dynamic> params) async {
    var ret = {_success: false, _message: ''};

    int port =
        params["port"] is String ? int.parse(params["port"]) : params["port"];
    bool local = params["local"];
    String type = params["type"];
    String pwd = params["password"];
    String user = params["username"];
    if (local == null) local = false;

    ret[_success] = await Server.checkPort(port);

    if (!ret[_success]) {
      return ret..[_message] = "Unable to bind to port";
    }

    if (user == null || user.isEmpty) user = 'dsa';

    provider.addNode(
        '/${params[_name]}', ServerNode.def(port, local, type, user, pwd));

    link.saveAsync();

    ret[_message] = 'Success';
    return ret;
  }
}

class EditServer extends SimpleNode {
  static const String isType = 'editServer';
  static const String pathName = 'Edit_Server';

  static const String _local = 'local';
  static const String _port = 'port';
  static const String _type = 'type';
  static const String _user = 'username';
  static const String _pass = 'password';
  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> def(
          bool local, int port, String type, String user) =>
      {
        r'$is': isType,
        r'$name': 'Edit Server',
        r'$invokable': 'write',
        r'$params': [
          {
            "name": _local,
            "type": "bool",
            "description": "Bind to Local Interface",
            "default": local
          },
          {"name": _port, "type": "number", 'editor': 'int', "default": port},
          {
            "name": _type,
            "type": "enum[${ServerNode.DataHost},${ServerNode.DataClient}]",
            "default": type,
            "description": "Data Type"
          },
          {
            "name": _user,
            "type": "string",
            'default': user,
            "placeholder": "Optional Username"
          },
          {
            "name": _pass,
            "type": "string",
            "editor": "password",
            'description': 'Leaving this blank will use any previous password',
            "placeholder": "Optional Password"
          }
        ],
        r'$columns': [
          {'name': _success, 'type': 'bool', 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ]
      };

  final LinkProvider link;

  EditServer(String path, this.link) : super(path);

  @override
  Future<Map<String, dynamic>> onInvoke(Map<String, dynamic> params) async {
    final ret = {_success: false, _message: ''};

    int port;
    if (params[_port] is int) {
      port = params[_port];
    } else if (params[_port] is num) {
      port = (params[_port] as num).toInt();
    } else {
      port = int.parse(params[_port], onError: (_) => null);
    }

    bool loc = params[_local] as bool;
    String ty = params[_type] as String;
    String u = params[_user] as String;
    String p = params[_pass] as String;

    var err = await (parent as ServerNode).updateConfig(port, loc, ty, u, p);

    if (err == null) {
      ret
        ..[_success] = true
        ..[_message] = 'Success!';
      link.saveAsync();
    } else {
      ret
        ..[_success] = false
        ..[_message] = 'Unable to update config: $err';
    }

    return ret;
  }
}

class ServerNode extends SimpleNode implements NodeManager {
  static const String isType = 'server';

  /// ServerNode acts as a Data Host
  static const String DataHost = 'Data Host';

  /// ServerNode acts as a Data Client
  static const String DataClient = 'Data Client';

  static const String _port = r'$server_port';
  static const String _local = r'$server_local';
  static const String _type = r'$server_type';
  static const String _user = r'$$server_username';
  static const String _pass = r'$$server_password';

  static const Duration _timeout = const Duration(seconds: 5);

  static Map<String, dynamic> def(
      int port, bool local, String type, String user, String pass) {
    var ret = <String, dynamic>{
      r'$is': isType,
      _port: port,
      _local: local,
      _type: type,
      _user: user,
      _pass: pass,
      RemoveNode.pathName: RemoveNode.def(),
      EditServer.pathName: EditServer.def(local, port, type, user)
    };

    if (type.toLowerCase() == 'data host') {
      ret[CreateNode.pathName] = CreateNode.def();
      ret[CreateValue.pathName] = CreateValue.def();
    }
    return ret;
  }

  Server server;

  final LinkProvider link;
  @override
  bool isDataHost = false;
  ServerNode(String path, this.link) : super(path);

  @override
  onCreated() async {
    var port = configs[_port];
    var local = configs[_local];
    var type = configs[_type];
    var user = configs[_user];
    var pwd = configs[_pass];

    if (type == 'Data Host') {
      isDataHost = true;
    }

    if (local == null) {
      local = false;
      configs[_local] = local;
    }

    if (type == null) {
      type = "Data Host";
      configs[_type] = type;
    }

    try {
      server = await Server.bind(local, port, user, pwd, this);
    } catch (e) {
      // TODO: Handle failed to start server
    }

    if (type == DataHost) {
      isDataHost = true;
      var nd = provider.getNode('$path/${CreateNode.pathName}');
      if (nd == null) {
        provider.addNode('$path/${CreateNode.pathName}', CreateNode.def());
      }
      nd = provider.getNode('$path/${CreateValue.pathName}');
      if (nd == null) {
        provider.addNode('$path/${CreateValue.pathName}', CreateValue.def());
      }
    }
  }

  @override
  onRemoving() async {
    if (server != null) {
      await server.close();
      server = null;
    }
  }

  Future<String> updateConfig(
      int port, bool local, String type, String user, String pass) async {
    if (pass == null || pass.isEmpty) {
      pass = getConfig(_pass);
    }

    if (server != null) {
      if (server.port == port && server.isLocal == local) {
        server.updateAuth(user, pass);
        if (type == DataHost) {
          isDataHost = true;
        } else {
          isDataHost = false;
        }
        configs[_type] = type;
        configs[_user] = user;
        configs[_pass] = pass;
        return null;
      }

      if (server.port != port) {
        var pOk = Server.checkPort(port);
        if (!pOk) {
          return 'Unable to bind to port: $port';
        }
      }

      await server.close();
    }

    try {
      server = await Server.bind(local, port, user, pass, this);
    } catch (e) {
      return e.toString();
    }

    if (type == DataHost) {
      isDataHost = true;
    } else {
      isDataHost = false;
    }

    configs[_type] = type;
    configs[_user] = user;
    configs[_pass] = pass;
    configs[_local] = local;
    configs[_port] = port;

    return null;
  }

  String _hostPath(String path) {
    var hostPath = "${this.path}$path";
    if (hostPath != "/" && hostPath.endsWith("/")) {
      hostPath = hostPath.substring(0, hostPath.length - 1);
    }
    return hostPath;
  }

  @override
  Future<ServerResponse> getRequest(ServerRequest sr) async {
    if (isDataHost) {
      return _getData(sr);
    }
    return _getClient(sr);
  }

  @override
  Future<ServerResponse> putRequest(ServerRequest sr, Map body) async {
    var hostPath = _hostPath(sr.path);
    var p = new Path(hostPath);

    var pathsToCreate = [];
    var mp = p.parent;
    while (!mp.isRoot) {
      if (!provider.hasNode(mp.path)) {
        pathsToCreate.add(mp.path);
      }
      mp = mp.parent;
    }

    for (var i = pathsToCreate.length - 1; i >= 0; i--) {
      provider.addNode(pathsToCreate[i], RestNode.def());
    }

    var nd = provider.getNode(hostPath);
    Map map;
    if (nd == null) {
      body[r'$is'] = RestNode.isType;
      nd = provider.addNode(hostPath, RestNode.def(body));
      map = _getNodeMap(nd, sr);
    } else {
      if (body.containsKey('?value')) {
        nd.updateValue(body['?value']);
        map = _getNodeMap(nd, sr);
      } else {
        map = _getNodeMap(nd, sr);
        map.addAll(body);
        map[r'$is'] = RestNode.isType;
        map.keys.where((x) => map[x] == null).toList().forEach(map.remove);
        nd.load(map);
      }
    }

    link.saveAsync();

    return new ServerResponse(map, ResponseStatus.ok);
  }

  @override
  Future<ServerResponse> deleteRequest(ServerRequest sr) async {
    if (!isDataHost)
      return new ServerResponse({'error': 'Data clients do not support DELETE'},
          ResponseStatus.notImplemented);

    var hostPath = _hostPath(sr.path);
    var node = provider.getNode(hostPath);

    if (node is! RestNode && node is! ServerNode) {
      return new ServerResponse(
          {'error': 'Not found'}, ResponseStatus.notFound);
    }

    var map = _getNodeMap(node, sr);
    node.remove();
    link.saveAsync();
    return new ServerResponse(map, ResponseStatus.ok);
  }

  @override
  Future<ServerResponse> postRequest(ServerRequest sr, dynamic body) async {
    if (isDataHost) {
      return _postData(sr, body);
    }

    if (body is Map && body.length == 1 && body.containsKey('?value')) {
      return _updateValue(sr, body as Map);
    }

    if (body is List && sr.path == '/_/vaues') {
      return _getMultiValues(sr, body as List);
    }

    if (sr.returnValue) {
      return _setRemoteNode(sr, body);
    }

    if (sr.isInvoke) {
      return _invokeRemoteNode(sr, body);
    }

    return _postClient(sr, body);
  }

  Future<ServerResponse> _setRemoteNode(ServerRequest sr, Map body) async {
    RemoteNode nd;
    try {
      await link.requester.set(sr.path, body).timeout(_timeout);
      nd = await link.requester.getRemoteNode(sr.path).timeout(_timeout);
    } on TimeoutException {
      return new ServerResponse(
          {'error': 'Server timed out accessing remote node: ${sr.path}'},
          ResponseStatus.error);
    }

    if (nd == null) {
      return new ServerResponse(
          {'error': 'Unable to find remote node: ${sr.path}'},
          ResponseStatus.notFound);
    }

    var map = await _getRemoteNodeMap(nd, sr);
    return new ServerResponse(map, ResponseStatus.ok);
  }

  Future<ServerResponse> _getMultiValues(ServerRequest sr, List body) async {
    var vals = body.where((el) => el is String).toList();
    var futs = <Future<ValueUpdate>>[];

    for (String key in vals) {
      futs.add(link.requester
          .getNodeValue(key)
          .timeout(_timeout, onTimeout: () => null));
    }

    var results = await Future.wait<ValueUpdate>(futs);
    var values = <String, dynamic>{};
    for (var i = 0; i < vals.length; i++) {
      values[vals[i]] = {'value': results[i].value, 'timestamp': results[i].ts};
    }

    return new ServerResponse(values, ResponseStatus.ok);
  }

  Future<ServerResponse> _updateValue(ServerRequest sr, Map body) async {
    var value = body['?value'];

    RemoteNode nd;
    try {
      await link.requester.set(sr.path, value).timeout(_timeout);
      nd = await link.requester.getRemoteNode(sr.path).timeout(_timeout);
    } on TimeoutException {
      logger.warning('Timed out trying to set value: $value on ${sr.path}');

      return new ServerResponse(
          {'error': 'Server timed out trying to set remote path: ${sr.path}'},
          ResponseStatus.error);
    }

    if (nd == null) {
      return new ServerResponse({'error': 'Unable to update value: ${sr.path}'},
          ResponseStatus.error);
    }

    var map = await _getRemoteNodeMap(nd, sr);
    return new ServerResponse(map, ResponseStatus.ok);
  }

  Future<ServerResponse> _invokeRemoteNode(ServerRequest sr, Map body) async {
    ServerResponse sendError(DSError error) => new ServerResponse({
          'error': {
            'message': error.msg,
            'detail': error.detail,
            'path': error.path,
            'phase': error.phase
          }
        }, ResponseStatus.error);

    RemoteNode node;
    try {
      node = await link.requester.getRemoteNode(sr.path).timeout(_timeout);
    } on TimeoutException {
      return new ServerResponse(
          {'error': 'Timed out trying to retreive remote node: ${sr.path}'},
          ResponseStatus.error);
    }

    if (node == null) {
      return new ServerResponse(
          {'error': 'Node not found'}, ResponseStatus.notFound);
    }

    if (node.configs[r'$invokable'] == null ||
        node.configs[r'$invokable'] == 'never') {
      return new ServerResponse(
          {'error': 'Node is not invokable'}, ResponseStatus.notImplemented);
    }

    var updates = <RequesterInvokeUpdate>[];
    var stream = link.requester.invoke(sr.path, body);
    var sub = stream.listen((RequesterInvokeUpdate up) => updates.add(up));

    int timeoutSec = sr.timeout ?? 30;
    if (timeoutSec >= 300) timeoutSec = 300;

    await sub.asFuture().timeout(new Duration(seconds: timeoutSec),
        onTimeout: () {
      sub.cancel();
    });

    if (sr.isBinary) {
      if (updates != null || updates.isNotEmpty) {
        for (var up in updates) {
          if (up.error != null) return sendError(up.error);

          for (List row in up.rows) {
            for (var c in row) {
              if (c is ByteData) {
                return new ServerResponse({
                  'data': c.buffer.asUint8List(c.offsetInBytes, c.lengthInBytes)
                }, ResponseStatus.binary);
              }
            }
          }
        }
      }

      return new ServerResponse(
          {'error': 'Not a binary invoke'}, ResponseStatus.badRequest);
    } // End binary

    var result = {'columns': [], 'rows': []};

    for (var up in updates) {
      if (up.error != null) return sendError(up.error);

      result['columns'].addAll(up.columns.map((x) => x.getData()).toList());
      result['rows'].addAll(up.rows);
    }

    return new ServerResponse(result, ResponseStatus.ok);
  }

  Future<ServerResponse> _postData(ServerRequest sr, dynamic body) async {
    var hostPath = _hostPath(sr.path);
    var node = provider.getNode(hostPath);

    var map = {};
    if (node == null) {
      node = provider.addNode(hostPath, body);
      map = _getNodeMap(node, sr);
      return new ServerResponse(map, ResponseStatus.ok);
    }

    if (body is Map && body.length == 1 && body.keys.contains('?value')) {
      node.updateValue(body['?value']);
      map = _getNodeMap(node, sr);
    } else if (body is Map) {
      node.load(RestNode.def(body));
      map = _getNodeMap(node, sr);
    } else if (sr.returnValue) {
      node.updateValue(body);
      map = _getNodeMap(node, sr);
    }

    link.saveAsync();
    return new ServerResponse(map, ResponseStatus.ok);
  }

  Future<ServerResponse> _postClient(ServerRequest sr, dynamic body) async {
    if (body is! Map ||
        !body.keys.every((kv) {
          var k = kv.toString();
          return k.startsWith('@') || k == '?value';
        })) {
      return new ServerResponse(
          {'error': 'Data client does not support updating nodes'},
          ResponseStatus.notImplemented);
    }

    var futs = <Future>[];
    for (var key in body.keys) {
      String p = sr.path;
      if (key != '?value') {
        p += '/$key';
      }

      futs.add(link.requester.set(p, body[key]));
    }

    await Future.wait(futs);
    RemoteNode nd;
    try {
      nd = await link.requester.getRemoteNode(sr.path).timeout(_timeout);
    } on TimeoutException {
      return new ServerResponse(
          {'error': 'Server timed out trying to set remote path: ${sr.path}'},
          ResponseStatus.error);
    }

    if (nd == null) {
      return new ServerResponse({'error': 'Unable to update value: ${sr.path}'},
          ResponseStatus.error);
    }

    var map = await _getRemoteNodeMap(nd, sr);
    return new ServerResponse(map, ResponseStatus.ok);
  }

  Future<Null> valueSubscribe(ServerRequest sr, WebSocket socket) async {
    // ARG! Why aren't these subclasses of one super class/interface!
    ReqSubscribeListener sub;
    RespSubscribeListener sub2;
    void remoteValueUpdate(ValueUpdate update) {
      if (socket.closeCode != null) {
        sub?.cancel();
        return;
      }

      var isBin = false;
      var value = update.value;
      if (value is ByteData) {
        value =
            value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
      }

      if (value is Uint8List) {
        isBin = true;
        value = BASE64.encode(value);
      }

      var msg = {'value': value, 'timestamp': update.ts};

      if (isBin) msg['bin'] = true;
      socket.add(JSON.encode(msg));
    }

    void hostValueUdate(ValueUpdate update) {
      if (socket.closeCode != null) {
        sub2?.cancel();
        return;
      }

      socket.add(JSON.encode({'value': update.value, 'timestamp': update.ts}));
    }

    if (isDataHost) {
      var hostPath = _hostPath(sr.path);
      var n = provider.getNode(hostPath);
      sub2 = n.subscribe(hostValueUdate);
    } else {
      sub = link.requester.subscribe(sr.path, remoteValueUpdate);
    }

    socket.done.then((_) {
      sub?.cancel();
      sub2?.cancel();
    });
  }

  Future<ServerResponse> _getClient(ServerRequest sr) async {
    var p = new Path(sr.path);
    if (!p.valid) {
      return new ServerResponse(
          {'error': 'Invalid Path: ${sr.path}'}, ResponseStatus.badRequest);
    }

    RemoteNode nd;
    var requester = link.requester;
    try {
      nd = await requester.getRemoteNode(p.path).timeout(_timeout);
    } catch (e) {
      return new ServerResponse(
          {'error': 'Server error $e'}, ResponseStatus.error);
    }

    if (nd == null) {
      return new ServerResponse(
          {'error': 'Node not found'}, ResponseStatus.notFound);
    }

    var body = await _getRemoteNodeMap(nd, sr);
    return new ServerResponse(body, ResponseStatus.ok);
  }

  Future<ServerResponse> _getData(ServerRequest sr) async {
    var hostPath = _hostPath(sr.path);

    var n = provider.getNode(hostPath);
    if (n == null) {
      return new ServerResponse(
          {'error': 'Node not found'}, ResponseStatus.notFound);
    }

    var map = _getNodeMap(n, sr);

    return new ServerResponse(map, ResponseStatus.ok);
  }

  Map<String, dynamic> _getNodeMap(SimpleNode n, ServerRequest req) {
    if (n == null || (n is! RestNode && n is! ServerNode))
      return {'error': 'No such node'};

    var map = {'?name': n.name, '?path': req.path};

    map..addAll(n.configs)..addAll(n.attributes);

    for (SimpleNode child in n.children.values) {
      if (child is! RestNode) continue;

      map[child.name] = {
        '?name': child.name,
        '?path': req.path + '/${child.name}'
      }..addAll(child.getSimpleMap());
    }

    if (n.lastValueUpdate != null && n.type != null) {
      map
        ..['?value'] = n.lastValueUpdate.value
        ..['?value_timestamp'] = n.lastValueUpdate.ts;
    }

    map.keys
        .where((String k) => k.startsWith(r'$$'))
        .toList()
        .forEach(map.remove);

    return map;
  }

  Future<Map> _getRemoteNodeMap(RemoteNode n, ServerRequest req) async {
    if (n == null) {
      return {'error': 'No Such Node'};
    }

    var map = {
      '?name': n.name,
      '?path': req.path,
      '?url': req.request.requestedUri.toString()
    };

    map..addAll(n.configs)..addAll(n.attributes);

    if (map[r'$type'] is String) {
      // Has a type set, regardles of the value
      var vals = await _getRemoteValues(req.path, req);
      if (vals != null) map.addAll(vals);
    }

    for (String key in n.children.keys) {
      var ch = n.children[key] as RemoteNode;

      var trp = (req.path == '/' ? "" : req.path) + '/$key';
      var m = {
        '?name': ch.name,
        '?path': trp,
        '?url': req.request.requestedUri
            .replace(path: Uri.encodeFull(trp))
            .toString()
      };

      m.addAll(ch.getSimpleMap());

      if (req.hasChildValues && m[r'$type'] is String) {
        var vals = await _getRemoteValues(trp, req);
        if (vals != null) m.addAll(vals);
      }

      map[key] = m;
    }

    return map;
  }

  Future<Map> _getRemoteValues(String path, ServerRequest req) async {
    var c = new Completer<ValueUpdate>();
    ReqSubscribeListener listener;
    listener = link.requester.subscribe(path, (ValueUpdate up) {
      if (!c.isCompleted) {
        c.complete(up);
      }

      if (listener != null) {
        listener.cancel();
        listener = null;
      }
    });

    var val = await c.future.timeout(_timeout, onTimeout: () {
      if (listener != null) {
        listener.cancel();
        listener = null;
      }
      return null;
    });

    if (val == null) return null;

    var value = val.value;
    if (req.returnValue) {
      if (value is ByteData) {
        value =
            value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
      }

      if (value is Uint8List) {
        value = BASE64.encode(value);
      }
    }

    var map = {'?value': value, '?value_timestamp': val.ts};

    return map;
  }
}
