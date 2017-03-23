import 'dart:async';

import 'package:dslink/dslink.dart';

import 'rest.dart';

class CreateValue extends SimpleNode {
  static const String isType = 'createMetric';
  static const String pathName = 'Create_Value';

  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> def() => {
        r"$name": "Create Value",
        r"$is": isType,
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [
          {"name": "name", "type": "string"},
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
            "editor": buildEnumType(
                ["none", "textarea", "password", "daterange", "date"]),
            "default": "none"
          }
        ],
        r"$columns": [
          {'name': _success, 'type': 'bool', 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ]
      };

  final LinkProvider link;

  CreateValue(String path, this.link) : super(path);

  @override
  Future<Map<String, dynamic>> onInvoke(Map<String, String> params) async {
    var ret = {_success: true, _message: 'Success!'};
    var name = params["name"];
    var editor = params["editor"];
    var type = params["type"];

    var parent = new Path(path).parent;

    var map = {r"$type": type, r"$writable": "write"};

    if (editor != null && editor.isNotEmpty) {
      map[r"$editor"] = editor;
    }

    provider.addNode("${parent.path}/${name}", RestNode.def(map));

    link.saveAsync();
    return ret;
  }
}

class CreateNode extends SimpleNode {
  static const String isType = 'create';
  static const String pathName = 'createNode';

  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> def() => {
        r"$name": "Create Node",
        r"$is": isType,
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [
          {"name": "name", "type": "string"}
        ],
        r'$columns': [
          {'name': _success, 'type': 'bool', 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ],
      };

  final LinkProvider link;

  CreateNode(String path, this.link) : super(path);

  @override
  Future<Map<String, dynamic>> onInvoke(Map<String, String> params) async {
    var ret = {_success: true, _message: 'Success!'};
    var name = params["name"];

    var parent = new Path(path).parent;
    provider.addNode("${parent.path}/${name}", RestNode.def());
    link.saveAsync();

    return ret;
  }
}
