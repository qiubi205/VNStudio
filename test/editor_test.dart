import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:vn_studio/models.dart';
import 'package:vn_studio/screens.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProvider();

  testWidgets('EditorScreen renders without exception', (tester) async {
    final dir = Directory(
        '${Directory.systemTemp.path}/vnstudio/projects/test123');
    await dir.create(recursive: true);
    final p = Project(id: 'test123', title: '测试作品');
    File('${dir.path}/project.json')
        .writeAsStringSync(jsonEncode(p.toJson()));

    await tester.pumpWidget(const MaterialApp(home: EditorScreen(projectId: 'test123')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final err = tester.takeException();
    expect(err, isNull, reason: '渲染异常: $err');
    expect(find.text('测试作品'), findsOneWidget);
    // 应显示三个 Tab
    expect(find.text('📝 剧本'), findsOneWidget);
    expect(find.text('🎨 资产'), findsOneWidget);
    expect(find.text('📦 导出'), findsOneWidget);
    // 画布工具栏提示
    expect(find.textContaining('点空白处创建节点'), findsOneWidget);
  });
}
