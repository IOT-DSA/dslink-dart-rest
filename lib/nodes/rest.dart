import 'package:dslink/dslink.dart';

import 'create_value.dart';
import 'remove.dart';

class RestNode extends SimpleNode {
  static const String isType = 'rest';

  static Map<String, dynamic> def(Map<String, dynamic> conf) {
    var ret = {
      CreateNode.pathName: CreateNode.def(),
      CreateValue.pathName: CreateValue.def(),
      RemoveNode.pathName: RemoveNode.def()
    };

    conf.forEach((String key, dynamic val) {
      ret[key] = val;
    });

    return ret;
  }

  RestNode(String path) : super(path);

}
