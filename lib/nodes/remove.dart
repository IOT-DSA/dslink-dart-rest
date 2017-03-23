import 'package:dslink/dslink.dart';

class RemoveNode extends SimpleNode {
  static const String isType = 'remove';
  static const String pathName = 'remove';

  static const String _success = 'success';
  static const String _message = 'message';

  static Map<String, dynamic> def() => {
        r'$is': isType,
        r'$name': 'Remove',
        r'$invokable': 'write',
        r'$params': [],
        r'$columns': [
          {'name': _success, 'type': 'bool', 'default': false},
          {'name': _message, 'type': 'string', 'default': ''}
        ]
      };

  final LinkProvider link;

  RemoveNode(String path, this.link) : super(path);

  @override
  Map<String, dynamic> onInvoke(Map<String, dynamic> params) {
    final ret = {_success: true, _message: 'Success!'};

    parent.remove();
    link.save();

    return ret;
  }
}
