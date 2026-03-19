import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageService {
  static const String chatBoxName = 'chat_box';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(chatBoxName);
  }

  Future<void> saveChat(String id, Map<String, dynamic> data) async {
    final box = Hive.box(chatBoxName);
    await box.put(id, data);
  }

  List<dynamic> getChats() {
    final box = Hive.box(chatBoxName);
    return box.values.toList();
  }
}

final storageServiceProvider = Provider((ref) => StorageService());
