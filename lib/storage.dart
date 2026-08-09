// VN Studio · 存储层：项目/脚本/资产/存档 的本地 JSON + 文件管理
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

class Storage {
  static Directory? _root;

  static Future<Directory> root() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/vnstudio');
    await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  static Future<Directory> projectsDir() async =>
      Directory('${(await root()).path}/projects');

  static Future<Directory> projectDir(String id) async =>
      Directory('${(await projectsDir()).path}/$id');

  static Future<Directory> assetsDir(String id) async {
    final d = Directory('${(await projectDir(id)).path}/assets');
    await d.create(recursive: true);
    return d;
  }

  static Future<Directory> exportsDir() async {
    final d = Directory('${(await root()).path}/exports');
    await d.create(recursive: true);
    return d;
  }

  // ---- 项目索引 ----
  static Future<List<Map<String, dynamic>>> loadIndex() async {
    final f = File('${(await root()).path}/index.json');
    if (!await f.exists()) return [];
    try {
      final l = jsonDecode(await f.readAsString()) as List;
      return l.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveIndex(List<Map<String, dynamic>> idx) async {
    final f = File('${(await root()).path}/index.json');
    await f.writeAsString(jsonEncode(idx));
  }

  // ---- 项目读写 ----
  static Future<Project?> loadProject(String id) async {
    final f = File('${(await projectDir(id)).path}/project.json');
    if (!await f.exists()) return null;
    try {
      return Project.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProject(Project p) async {
    p.updated = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await (await projectDir(p.id)).create(recursive: true);
    await File('${(await projectDir(p.id)).path}/project.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(p.toJson()));
    final idx = await loadIndex();
    var found = false;
    for (final e in idx) {
      if (e['id'] == p.id) {
        e['title'] = p.title;
        e['desc'] = p.desc;
        e['updated'] = p.updated;
        found = true;
        break;
      }
    }
    if (!found) {
      idx.insert(0, {
        'id': p.id,
        'title': p.title,
        'desc': p.desc,
        'created': p.created,
        'updated': p.updated,
      });
    }
    await saveIndex(idx);
  }

  static Future<void> deleteProject(String id) async {
    final d = await projectDir(id);
    if (await d.exists()) await d.delete(recursive: true);
    final idx = await loadIndex();
    idx.removeWhere((e) => e['id'] == id);
    await saveIndex(idx);
  }

  // ---- 资产 ----
  static Future<List<File>> listAssets(String id) async {
    final d = await assetsDir(id);
    final files = d.listSync().whereType<File>().toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static Future<String> copyIntoAssets(
      String projectId, String srcPath, String originalName) async {
    final dir = await assetsDir(projectId);
    final name = sanitizeName(originalName);
    var finalName = name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (await File('${dir.path}/$finalName').exists()) {
      finalName = '${base}_$i$ext';
      i++;
    }
    await File(srcPath).copy('${dir.path}/$finalName');
    return finalName;
  }

  static String sanitizeName(String name) {
    var n = name.replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fff]'), '_');
    if (n.length > 100) n = n.substring(n.length - 100);
    return n.isEmpty
        ? 'file_${DateTime.now().millisecondsSinceEpoch}'
        : n;
  }

  // ---- 游戏存档（播放器进度） ----
  static Future<Map<String, dynamic>?> loadSave(String projectId) async {
    final f = File('${(await projectDir(projectId)).path}/save.json');
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveGame(String projectId, String scene, int idx) async {
    final f = File('${(await projectDir(projectId)).path}/save.json');
    await f.writeAsString(jsonEncode({'scene': scene, 'idx': idx}));
  }

  static Future<void> clearSave(String projectId) async {
    final f = File('${(await projectDir(projectId)).path}/save.json');
    if (await f.exists()) await f.delete();
  }
}
