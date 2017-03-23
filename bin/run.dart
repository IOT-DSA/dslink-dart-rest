import "dart:async";

import "package:dslink/dslink.dart";

import 'package:dslink_rest/rest.dart';

Future<Null> main(List<String> args) async {
  LinkProvider link;
  link = new LinkProvider(args, "REST-",
      profiles: {
        AddServer.isType: (String path) => new AddServer(path, link),
        EditServer.isType: (String path) => new EditServer(path, link),
        ServerNode.isType: (String path) => new ServerNode(path, link),
        CreateValue.isType: (String path) => new CreateValue(path, link),
        CreateNode.isType: (String path) => new CreateNode(path, link),
        RemoveNode.isType: (String path) => new RemoveNode(path, link),
        RestNode.isType: (String path) => new RestNode(path),
      },
      defaultNodes: {AddServer.pathName: AddServer.def()},
      autoInitialize: false,
      isRequester: true,
      isResponder: true);

  link.init();
  await link.connect();
}
