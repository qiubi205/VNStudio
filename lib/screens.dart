// VN Studio · 全部界面：首页 / 编辑器(剧本·资产·导出) / AI 生成 / 设置 / 播放器
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'models.dart';
import 'storage.dart';
import 'services.dart';

// ================================================================ 首页
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final idx = await Storage.loadIndex();
    if (!mounted) return;
    setState(() {
      _projects = idx;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final desc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('新建作品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(
                    labelText: '标题', hintText: '例如：与优香的放学后')),
            const SizedBox(height: 8),
            TextField(
                controller: desc,
                decoration: const InputDecoration(labelText: '简介（可选）')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final t = title.text.trim();
    final p = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: t.isEmpty ? '未命名作品' : t,
      desc: desc.text.trim(),
    );
    await Storage.saveProject(p);
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => EditorScreen(projectId: p.id)));
  }

  Future<void> _delete(Map<String, dynamic> proj) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除作品'),
        content: Text('确定删除《${proj['title']}》吗？剧本和素材将一并删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await Storage.deleteProject(proj['id'] as String);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VN Studio · 视觉小说工坊'),
        actions: [
          IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'AI 设置',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('新建作品'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_stories, size: 64, color: Colors.white24),
                        SizedBox(height: 16),
                        Text('还没有作品\n点右下角「新建作品」开始，\n或先在右上角设置里填入 AI 密钥，让 AI 帮你写剧本',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: _projects.length,
                  itemBuilder: (c, i) {
                    final proj = _projects[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book, size: 32),
                        title: Text('${proj['title']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 17)),
                        subtitle: Text(
                          '${proj['desc']?.toString().isNotEmpty == true ? '${proj['desc']}\n' : ''}'
                          '更新于 ${fmtTime((proj['updated'] as num?)?.toInt() ?? 0)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(proj),
                        ),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => EditorScreen(
                                    projectId: proj['id'] as String))),
                      ),
                    );
                  },
                ),
    );
  }
}

// ================================================================ 编辑器
class EditorScreen extends StatefulWidget {
  final String projectId;
  const EditorScreen({super.key, required this.projectId});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Project? _p;
  List<File> _assets = [];
  int _tab = 0;
  String? _sel;
  bool _busy = false;
  AudioPlayer? _preview;
  /// 画布视口：缩放与平移（交互视图）
  double _viewportScale = 1.0;
  Offset _viewportOffset = Offset.zero;
  double _scaleStartScale = 1.0;
  Offset _scaleStartOffset = Offset.zero;
  Offset _scaleStartFocal = Offset.zero;
  /// 拖动中的节点（画布视口拖拽时记录）
  String? _dragNodeId;
  /// 画布世界尺寸（节点坐标 = x/y × 世界尺寸；缩放/平移只是视口变换，世界不变）
  static const double _worldW = 1200;
  static const double _worldH = 1800;
  /// 最近一次画布视口尺寸（缩放锚点计算用）
  double _viewW = 0;
  double _viewH = 0;
  /// 首次布局时自动把整个世界适配进屏幕
  bool _viewInit = false;
  /// 串联模式：先点起点再点终点（_linkKind 决定主线还是选项分支）
  bool _linkMode = false;
  String? _linkFrom;
  /// 串联类型：主线（next）/ 选项分支（choices）
  _LinkKind _linkKind = _LinkKind.next;
  /// 选项分支模式：起点确认后暂存选项文字
  String? _pendingChoiceText;
  /// 画布重设目标模式（点目标节点完成）
  _Retarget? _retarget;
  /// 当前选中的连线（画布高亮）
  _LinkKey? _selLink;
  /// 表单版本号：剧本整体替换（新建/AI 应用/加载）时自增，强制重建编辑器表单

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await Storage.loadProject(widget.projectId);
    final assets = await Storage.listAssets(widget.projectId);
    if (!mounted) return;
    setState(() {
      _p = p;
      _assets = assets;
      if (p != null && p.script.scenes.isNotEmpty) _sel = p.script.scenes.first.id;
    });
  }

  Future<void> _refreshAssets() async {
    final assets = await Storage.listAssets(widget.projectId);
    if (!mounted) return;
    setState(() => _assets = assets);
  }

  void _save() {
    final p = _p;
    if (p == null) return;
    Storage.saveProject(p);
  }

  void _mutate(VoidCallback fn) {
    setState(fn);
    _save();
  }

  String _name(File f) => f.path.split(Platform.pathSeparator).last;
  List<String> _imageNames() =>
      _assets.where((f) => ExportService.isImage(f.path)).map(_name).toList();
  List<String> _bgmNames() =>
      _assets.where((f) => ExportService.isAudio(f.path)).map(_name).toList();

  Scene? _current() {
    final p = _p;
    if (p == null || _sel == null) return null;
    return p.script.findScene(_sel!);
  }

  // ---------- 剧本操作（画布节点版） ----------
  /// 点画布空白处创建节点
  void _addSceneAt(double rx, double ry) {
    final p = _p;
    if (p == null) return;
    var n = 1;
    final ids = p.script.scenes.map((s) => s.id).toSet();
    while (ids.contains('s$n')) {
      n++;
    }
    final sc = Scene(
        id: 's$n',
        name: '场景 $n',
        x: rx.clamp(0.05, 0.95),
        y: ry.clamp(0.05, 0.95));
    _mutate(() {
      p.script.scenes.add(sc);
      _sel = sc.id;
    });
    _toast('已创建「${sc.name}」，用下方工具栏添加内容');
  }

  void _renameScene(Scene sc) {
    final ctrl = TextEditingController(text: sc.name);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重命名节点'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '场景名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isNotEmpty) _mutate(() => sc.name = v);
                Navigator.pop(c);
              },
              child: const Text('确定')),
        ],
      ),
    );
  }

  /// 添加一句剧情并立即打开剧情编辑面板
  void _addStoryLine(Scene sc) {
    _mutate(() => sc.dialogue.add(Line()));
    _editStory(sc);
  }

  void _delScene() {
    final p = _p;
    final sc = _current();
    if (p == null || sc == null) return;
    showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除场景'),
        content: Text('删除「${sc.name}」？引用它的选项将失效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    ).then((ok) {
      if (ok != true || !mounted) return;
      _mutate(() {
        p.script.scenes.removeWhere((s) => s.id == sc.id);
        _selLink = null;
        for (final s in p.script.scenes) {
          if (s.next == sc.id) s.next = '';
          for (final ch in s.choices) {
            if (ch.next == sc.id) ch.next = '';
          }
        }
        _sel = p.script.scenes.isNotEmpty ? p.script.scenes.first.id : null;
      });
    });
  }

  /// 台词移动/删除（剧情面板内使用）
  void _moveLine(Scene sc, int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= sc.dialogue.length) return;
    _mutate(() {
      final t = sc.dialogue[i];
      sc.dialogue[i] = sc.dialogue[j];
      sc.dialogue[j] = t;
    });
  }

  void _delLine(Scene sc, int i) {
    if (i < 0 || i >= sc.dialogue.length) return;
    _mutate(() => sc.dialogue.removeAt(i));
  }

  void _moveChoice(Scene sc, int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= sc.choices.length) return;
    _mutate(() {
      final t = sc.choices[i];
      sc.choices[i] = sc.choices[j];
      sc.choices[j] = t;
    });
  }

  void _delChoice(Scene sc, int i) {
    if (i < 0 || i >= sc.choices.length) return;
    _mutate(() => sc.choices.removeAt(i));
  }

  /// 字符串列表（CG/BGM 素材）移动/删除
  void _moveStr(List<String> l, int i, int dir) {
    final j = i + dir;
    if (j < 0 || j >= l.length) return;
    _mutate(() {
      final t = l[i];
      l[i] = l[j];
      l[j] = t;
    });
  }

  void _delStr(List<String> l, int i) {
    if (i < 0 || i >= l.length) return;
    _mutate(() => l.removeAt(i));
  }

  void _setTitle(String v) {
    final p = _p;
    if (p == null) return;
    _mutate(() => p.title = v);
  }

  void _setSummary(String v) {
    final p = _p;
    if (p == null) return;
    _mutate(() => p.script.summary = v);
  }
  // ---------- AI ----------
  Future<void> _ai() async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const AiDialog());
    if (result == null || !mounted) return;
    final script = result['script'] as Script;
    final demo = (result['demo'] as bool?) ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('AI 剧本生成完成'),
        content: Text(
            '${demo ? '（示例剧本：未配置 AI 密钥）\n' : ''}'
            '《${script.title}》\n共 ${script.scenes.length} 个场景\n\n'
            '将替换当前剧本（AI 提示信息会保留，可继续手动编辑）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('应用')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _mutate(() {
      _p!.script = script;
      AiService.autoAddCharacters(_p!);
      _sel = script.scenes.isNotEmpty ? script.scenes.first.id : null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(demo
            ? '已应用示例剧本（在设置中填入 AI 密钥后可生成真剧本）'
            : '✅ 剧本已应用，可自由编辑')));
  }

  // ---------- 导出 ----------
  Future<void> _export() async {
    final p = _p;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await ExportService.buildZip(p);
      if (!mounted) return;
      await Share.shareXFiles([XFile(path)],
          text: 'VN Studio 导出：${p.title}（project.json + assets，agent 可加工）');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已导出并唤起分享，文件同时保存在 $path')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- 播放 ----------
  void _play() {
    final p = _p;
    if (p == null) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PlayerScreen(project: p)));
  }

  // ============ UI 构建 ============
  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(p.title.isEmpty ? '未命名作品' : p.title),
          actions: [
            IconButton(
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'AI 生成剧本',
                onPressed: _ai),
            IconButton(
                icon: const Icon(Icons.play_circle_outline),
                tooltip: '试玩',
                onPressed: _play),
            IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: '导出项目包',
                onPressed: _export),
          ],
        ),
        body: Column(
          children: [
            TabBar(
              tabs: const [
                Tab(text: '📝 剧本'),
                Tab(text: '🎨 资产'),
                Tab(text: '📦 导出'),
              ],
              onTap: (i) => setState(() => _tab = i),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _buildScriptTab(),
                  _buildAssetsTab(),
                  _buildExportTab()
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 剧本 Tab（画布节点编辑器） ----------------
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Widget _buildScriptTab() {
    final p = _p!;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (c, cons) {
              final w = cons.maxWidth;
              final h = cons.maxHeight;
              _viewW = w;
              _viewH = h;
              // 首次布局：把整个世界适配进屏幕，保证节点再多也能全景查看
              if (!_viewInit) {
                _viewInit = true;
                _fitView(w, h);
              }
              // 节点中心点（画布世界坐标；旧数据 x/y=-1 按索引铺开）
              final centers = <Offset>[
                for (var i = 0; i < p.script.scenes.length; i++)
                  Offset(_rx(p.script.scenes[i], i), _ry(p.script.scenes[i], i))
              ];
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) {
                        final pt = _toCanvas(d.localPosition);
                        final hit = _hitTestNode(pt);
                        if (hit != null) {
                          _onNodeTap(hit);
                        } else {
                          final link = _hitTestLink(pt);
                          if (link != null) {
                            _onLinkTap(link);
                          } else if (!_linkMode && _retarget == null) {
                            _addSceneAt(pt.dx / _worldW, pt.dy / _worldH);
                          }
                        }
                      },
                      onScaleStart: (d) {
                        _scaleStartScale = _viewportScale;
                        _scaleStartOffset = _viewportOffset;
                        _scaleStartFocal = d.localFocalPoint;
                        if (d.pointerCount == 1) {
                          final pt = _toCanvas(d.localFocalPoint);
                          _dragNodeId = _hitTestNode(pt)?.id;
                        }
                      },
                      onScaleUpdate: (d) {
                        if (d.pointerCount >= 2) {
                          // 双指缩放：保持焦点处的画布点不动
                          final ns =
                              (_scaleStartScale * d.scale).clamp(0.15, 4.0);
                          final canvasAtFocal = (_scaleStartFocal -
                                  _scaleStartOffset) /
                              _scaleStartScale;
                          setState(() {
                            _viewportScale = ns;
                            _viewportOffset =
                                d.localFocalPoint - canvasAtFocal * ns;
                            _clampViewport();
                          });
                        } else if (d.pointerCount == 1 &&
                            _dragNodeId != null) {
                          // 单指拖动节点（世界坐标）
                          final sc = p.script.findScene(_dragNodeId!);
                          if (sc != null) {
                            final pt = _toCanvas(d.localFocalPoint);
                            _mutate(() {
                              sc.x = (pt.dx / _worldW).clamp(0.01, 0.99);
                              sc.y = (pt.dy / _worldH).clamp(0.01, 0.99);
                            });
                          }
                        } else if (d.pointerCount == 1) {
                          // 单指拖空白：平移视口
                          setState(() {
                            _viewportOffset = _scaleStartOffset +
                                (d.localFocalPoint - _scaleStartFocal);
                            _clampViewport();
                          });
                        }
                      },
                      onScaleEnd: (_) => _dragNodeId = null,
                      child: ClipRect(
                        child: Transform(
                          transform: Matrix4(
                            _viewportScale, 0, 0, 0, //
                            0, _viewportScale, 0, 0, //
                            0, 0, 1, 0, //
                            _viewportOffset.dx, _viewportOffset.dy, 0, 1,
                          ),
                          child: SizedBox(
                            width: _worldW,
                            height: _worldH,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                    child: Container(
                                  color: const Color(0xFF25252B),
                                  child: const CustomPaint(
                                      painter: _DotGridPainter()),
                                )),
                                Positioned.fill(
                                    child: CustomPaint(
                                        painter: _LinkPainter(
                                            p.script.scenes, centers,
                                            _selLink))),
                                for (var i = 0;
                                    i < p.script.scenes.length;
                                    i++)
                                  _nodeWidget(p.script.scenes[i], i),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 画布信息角标：节点数 / 缩放百分比 + 缩放按钮（+/−/适配）
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${p.script.scenes.length} 节点 · 缩放 ${(_viewportScale * 100).round()}%'
                            '${_linkMode ? (_linkKind == _LinkKind.next ? ' · 🔗主线' : ' · 🔀选项') : ''}'
                            '${_retarget != null ? ' · 🎯选目标' : ''}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white70),
                          ),
                          _cornerBtn(Icons.zoom_out, '缩小', () => _zoomBy(0.8)),
                          _cornerBtn(
                              Icons.zoom_in, '放大', () => _zoomBy(1.25)),
                          _cornerBtn(
                              Icons.fit_screen, '适配全部节点', _fitBtn),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (_linkMode || _retarget != null) _modeBanner(),
        _toolbar(),
      ],
    );
  }

  /// 节点画布坐标（x/y=-1 的旧数据按索引自动铺开；单位：世界坐标）
  double _rx(Scene sc, int i) {
    if (sc.x >= 0) return sc.x * _worldW;
    return (0.12 + (i * 0.23) % 0.68) * _worldW;
  }

  double _ry(Scene sc, int i) {
    if (sc.y >= 0) return sc.y * _worldH;
    return (0.16 + (i * 0.19) % 0.62) * _worldH;
  }

  /// 屏幕坐标 → 画布世界坐标（考虑视口缩放/平移）
  Offset _toCanvas(Offset screen) => Offset(
        (screen.dx - _viewportOffset.dx) / _viewportScale,
        (screen.dy - _viewportOffset.dy) / _viewportScale,
      );

  /// 命中检测：返回被点中的节点（画布世界坐标）
  Scene? _hitTestNode(Offset pt) {
    final p = _p;
    if (p == null) return null;
    for (var i = 0; i < p.script.scenes.length; i++) {
      final sc = p.script.scenes[i];
      final left = (_rx(sc, i) - 76).clamp(4.0, _worldW - 152);
      final top = (_ry(sc, i) - 24).clamp(4.0, _worldH - 120);
      if (pt.dx >= left &&
          pt.dx <= left + 152 &&
          pt.dy >= top &&
          pt.dy <= top + 64) {
        return sc;
      }
    }
    return null;
  }

  /// 连线命中检测：返回命中的链接（画布世界坐标）
  _LinkKey? _hitTestLink(Offset pt) {
    final p = _p;
    if (p == null) return null;
    const threshold = 14.0;
    _LinkKey? best;
    var bestDist = threshold;
    for (final sc in p.script.scenes) {
      final a = Offset(
          _rx(sc, p.script.scenes.indexOf(sc)),
          _ry(sc, p.script.scenes.indexOf(sc)));
      if (sc.next.isNotEmpty) {
        final t = p.script.findScene(sc.next);
        if (t != null) {
          final b = Offset(
              _rx(t, p.script.scenes.indexOf(t)),
              _ry(t, p.script.scenes.indexOf(t)));
          final d = _distToLink(a, b, pt);
          if (d < bestDist) {
            bestDist = d;
            best = _LinkKey(sc.id, false, 0);
          }
        }
      }
      for (var i = 0; i < sc.choices.length; i++) {
        final ch = sc.choices[i];
        if (ch.next.isEmpty) continue;
        final t = p.script.findScene(ch.next);
        if (t == null) continue;
        final b = Offset(
            _rx(t, p.script.scenes.indexOf(t)),
            _ry(t, p.script.scenes.indexOf(t)));
        final d = _distToLink(a, b, pt);
        if (d < bestDist) {
          bestDist = d;
          best = _LinkKey(sc.id, true, i);
        }
      }
    }
    return best;
  }

  /// 点到连线路径的距离（沿路径采样）
  double _distToLink(Offset a, Offset b, Offset pt) {
    final path = linkPath(a, b);
    var best = double.infinity;
    for (final m in path.computeMetrics()) {
      final len = m.length;
      for (var d = 0.0; d <= len; d += 3.0) {
        final t = m.getTangentForOffset(d);
        if (t == null) continue;
        final dist = (t.position - pt).distance;
        if (dist < best) best = dist;
      }
    }
    return best;
  }

  /// 点节点：串联/重设目标模式下选源或目标，否则选中
  void _onNodeTap(Scene sc) {
    final r = _retarget;
    if (r != null) {
      final src = _p!.script.findScene(r.sourceId);
      if (src != null) {
        if (r.choiceIndex < 0) {
          _mutate(() => src.next = sc.id);
          _toast('✅ 主线 →「${sc.name}」');
        } else if (r.choiceIndex < src.choices.length) {
          _mutate(() => src.choices[r.choiceIndex].next = sc.id);
          _toast('✅ 选项 →「${sc.name}」');
        }
      }
      setState(_clearModes);
      return;
    }
    if (_linkMode) {
      if (_linkFrom == null) {
        setState(() => _linkFrom = sc.id);
        if (_linkKind == _LinkKind.choice) {
          _promptChoiceText(sc);
        } else {
          _toast('已选起点「${sc.name}」，再点一个节点作为下一场景');
        }
      } else if (_linkFrom == sc.id) {
        setState(() {
          _linkFrom = null;
          _pendingChoiceText = null;
        });
        _toast('已取消选择');
      } else {
        final from = _p!.script.findScene(_linkFrom!);
        if (from != null) {
          if (_linkKind == _LinkKind.next) {
            _mutate(() => from.next = sc.id);
            _toast('✅ 主线「${from.name}」→「${sc.name}」');
          } else {
            final text = (_pendingChoiceText ?? '').trim();
            final t = text.isEmpty ? '选项 ${from.choices.length + 1}' : text;
            _mutate(() => from.choices.add(Choice(text: t, next: sc.id)));
            _toast('✅ 选项「$t」→「${sc.name}」');
          }
        }
        setState(() {
          _pendingChoiceText = null;
          _linkFrom = null;
        });
      }
      return;
    }
    setState(() => _sel = sc.id);
  }

  /// 点连线：选中并打开对应编辑面板
  void _onLinkTap(_LinkKey key) {
    final p = _p;
    if (p == null) return;
    final sc = p.script.findScene(key.sourceId);
    if (sc == null) return;
    setState(() => _selLink = key);
    if (!key.isChoice) {
      _editNextLinkDialog(sc);
    } else if (key.index < sc.choices.length) {
      _editChoiceDialog(null, null, sc, key.index, allowDelete: true);
    }
  }

  /// 选项分支模式：先输入选项文字，再点目标节点
  Future<void> _promptChoiceText(Scene sc) async {
    final ctrl = TextEditingController(text: '选项 ${sc.choices.length + 1}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('选项分支'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '选项文字（如：去森林）'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('下一步')),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      setState(_clearModes);
      return;
    }
    setState(() {
      _pendingChoiceText = ctrl.text.trim();
      _linkFrom = sc.id;
    });
    _toast('已选起点「${sc.name}」，再点一个目标节点完成选项分支');
  }

  /// 清空所有连线/重设目标模式
  void _clearModes() {
    _linkMode = false;
    _linkFrom = null;
    _pendingChoiceText = null;
    _retarget = null;
  }

  /// 进入“在画布上点选目标”模式（choiceIndex=-1 表示主线）
  void _startRetarget(String sourceId, int choiceIndex) {
    final src = _p?.script.findScene(sourceId);
    setState(() {
      _clearModes();
      _retarget = _Retarget(sourceId, choiceIndex);
    });
    _toast('🎯 在画布上点目标节点（从「${src?.name ?? sourceId}」出发）');
  }

  Widget _nodeWidget(Scene sc, int i) {
    final active = sc.id == _sel;
    final linking = (_linkMode && sc.id == _linkFrom) ||
        (_retarget != null && _retarget!.sourceId == sc.id);
    final left = (_rx(sc, i) - 76).clamp(4.0, _worldW - 152);
    final top = (_ry(sc, i) - 24).clamp(4.0, _worldH - 120);
    return Positioned(
      left: left,
      top: top,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onNodeTap(sc),
            child: Container(
              width: 152,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF3D4A9E)
                    : (linking ? const Color(0xFF1E6B3A) : const Color(0xFF3A3A42)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? const Color(0xFFFFC24B)
                      : (linking ? const Color(0xFF4ADE80) : Colors.white24),
                  width: active || linking ? 2 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sc.name.isEmpty ? sc.id : sc.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sc.dialogue.length} 句 · ${sc.choices.length} 选项',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (sc.dialogue.isNotEmpty)
            _contentChip('📄 剧情 ×${sc.dialogue.length}',
                const Color(0xFF3A6FB0), () => _editStory(sc)),
          if (sc.cgs.isNotEmpty)
            _contentChip('🖼 CG ×${sc.cgs.length}', const Color(0xFF8A4FA8),
                () => _editCgs(sc)),
          if (sc.bgms.isNotEmpty)
            _contentChip('🎵 BGM ×${sc.bgms.length}',
                const Color(0xFF2E8B67), () => _editBgms(sc)),
        ],
      ),
    );
  }

  Widget _contentChip(String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final sc = _current();
    final linkMenu = PopupMenuButton<_LinkAction>(
      icon: Icon(Icons.link,
          size: 20,
          color: (_linkMode || _retarget != null)
              ? const Color(0xFF4ADE80)
              : null),
      tooltip: '连接：主线 / 选项分支 / 管理',
      onSelected: (a) {
        switch (a) {
          case _LinkAction.next:
            setState(() {
              _clearModes();
              _linkMode = true;
              _linkKind = _LinkKind.next;
            });
            _toast('🔗 主线串联模式：点起点节点 → 再点目标节点');
            break;
          case _LinkAction.choice:
            setState(() {
              _clearModes();
              _linkMode = true;
              _linkKind = _LinkKind.choice;
            });
            _toast('🔀 选项分支模式：点起点节点，输入选项文字后点目标节点');
            break;
          case _LinkAction.manage:
            if (sc != null) _manageLinks(sc);
            break;
        }
      },
      itemBuilder: (c) => [
        const PopupMenuItem(
            value: _LinkAction.next, child: Text('🔗 设置主线（串联模式）')),
        const PopupMenuItem(
            value: _LinkAction.choice, child: Text('🔀 添加选项分支（串联模式）')),
        if (sc != null)
          const PopupMenuItem(
              value: _LinkAction.manage,
              child: Text('🗂 管理连接（主线/选项列表）')),
      ],
    );
    return Container(
      color: const Color(0xFF1C1C22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        top: false,
        child: sc == null
            ? Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _openProjectSettings,
                      child: const Text(
                        '点空白处创建节点 · 双指缩放/拖动平移 · 左上角可缩放\n点节点选中，点连线编辑连接（点这里改作品标题/简介）',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ),
                  ),
                  linkMenu,
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: '作品设置',
                    onPressed: _openProjectSettings,
                  ),
                ],
              )
            : Row(
                children: [
                  _toolBtn(Icons.chat_bubble_outline, '剧情内容',
                      () => _addStoryLine(sc)),
                  const SizedBox(width: 6),
                  _toolBtn(Icons.image_outlined, 'CG', () => _addCgTo(sc)),
                  const SizedBox(width: 6),
                  _toolBtn(
                      Icons.music_note_outlined, 'BGM', () => _addBgmTo(sc)),
                  const SizedBox(width: 6),
                  linkMenu,
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: '重命名节点',
                    onPressed: () => _renameScene(sc),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.redAccent),
                    tooltip: '删除节点',
                    onPressed: _delScene,
                  ),
                ],
              ),
      ),
    );
  }

  /// 模式提示条（串联/重设目标时显示，可一键取消）
  Widget _modeBanner() {
    final r = _retarget;
    String text;
    if (r != null) {
      final src = _p?.script.findScene(r.sourceId);
      text = '🎯 重设目标：「${src?.name ?? r.sourceId}」→ 点画布上的目标节点';
    } else if (_linkFrom != null) {
      final src = _p?.script.findScene(_linkFrom!);
      text = _linkKind == _LinkKind.choice
          ? '🔀 选项分支：「${src?.name ?? ''}」→ 再点目标节点'
          : '🔗 主线串联：「${src?.name ?? ''}」→ 再点目标节点';
    } else {
      text = _linkKind == _LinkKind.choice
          ? '🔀 选项分支模式：点一个节点作为起点'
          : '🔗 主线串联模式：点一个节点作为起点';
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFF2A2A33),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => setState(_clearModes),
            child:
                const Text('取消', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 适配全部节点到视口（按钮入口）
  void _fitBtn() => setState(() => _fitView(_viewW, _viewH));

  /// 角标小按钮
  Widget _cornerBtn(IconData icon, String tip, VoidCallback onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 15,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      icon: Icon(icon, color: Colors.white70),
      tooltip: tip,
      onPressed: onTap,
    );
  }

  /// 视口适配：把整个世界缩放到视口内（首次打开/重置时调用）
  void _fitView(double w, double h) {
    if (w <= 0 || h <= 0) return;
    final s = ((w / _worldW) < (h / _worldH) ? (w / _worldW) : (h / _worldH)) *
        0.92;
    _viewportScale = s.clamp(0.15, 4.0);
    _viewportOffset = Offset(
        (w - _worldW * _viewportScale) / 2,
        (h - _worldH * _viewportScale) / 2);
    _clampViewport();
  }

  /// 以视口中心为锚点缩放（+/- 按钮）
  void _zoomBy(double factor) {
    final w = _viewW, h = _viewH;
    if (w <= 0 || h <= 0) return;
    setState(() {
      final ns = (_viewportScale * factor).clamp(0.15, 4.0);
      final center = Offset(w / 2, h / 2);
      final canvasAtCenter = (center - _viewportOffset) / _viewportScale;
      _viewportScale = ns;
      _viewportOffset = center - canvasAtCenter * ns;
      _clampViewport();
    });
  }

  /// 防止把世界拖出屏幕：至少保留 40px 可视边距
  void _clampViewport() {
    final w = _viewW, h = _viewH;
    if (w <= 0 || h <= 0) return;
    const m = 40.0;
    final sw = _worldW * _viewportScale;
    final sh = _worldH * _viewportScale;
    double cx(double o, double worldS, double view) {
      if (worldS <= view) {
        final base = (view - worldS) / 2;
        return o.clamp(base - m, base + m);
      }
      return o.clamp(view - worldS - m, m);
    }

    _viewportOffset = Offset(
        cx(_viewportOffset.dx, sw, w), cx(_viewportOffset.dy, sh, h));
  }

  Widget _toolBtn(IconData icon, String label, VoidCallback onTap) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10)),
    );
  }

  // ---------- 作品设置 / 节点内容 ----------
  void _openProjectSettings() {
    final p = _p;
    if (p == null) return;
    final titleCtrl = TextEditingController(text: p.title);
    final sumCtrl = TextEditingController(text: p.script.summary);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('作品设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '作品标题')),
            const SizedBox(height: 8),
            TextField(
                controller: sumCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '简介')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                _setTitle(titleCtrl.text.trim());
                _setSummary(sumCtrl.text.trim());
                Navigator.pop(c);
              },
              child: const Text('保存')),
        ],
      ),
    );
  }

  Future<void> _addCgTo(Scene sc) async {
    final names = _imageNames();
    if (names.isEmpty) {
      _toast('还没有图片资产，请先到「🎨 资产」页上传');
      return;
    }
    final picked = await _pickAssetDialog('选择 CG 图片', names);
    if (picked == null || !mounted) return;
    _mutate(() {
      if (!sc.cgs.contains(picked)) sc.cgs.add(picked);
    });
  }

  Future<void> _addBgmTo(Scene sc) async {
    final names = _bgmNames();
    if (names.isEmpty) {
      _toast('还没有音乐资产，请先到「🎨 资产」页上传');
      return;
    }
    final picked = await _pickAssetDialog('选择 BGM 音乐', names);
    if (picked == null || !mounted) return;
    _mutate(() {
      if (!sc.bgms.contains(picked)) sc.bgms.add(picked);
    });
  }

  Future<String?> _pickAssetDialog(String title, List<String> names) {
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: names.length,
            itemBuilder: (c, i) => ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file, size: 18),
              title: Text(names[i],
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(c, names[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
        ],
      ),
    );
  }

  void _editStory(Scene sc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF232329),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          final charNames = _p!.characters.map((e) => e.name).toList();
          final images = _imageNames();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            maxChildSize: 0.95,
            builder: (c, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('📄 剧情内容',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(c)),
                  ],
                ),
                Text('节点：${sc.name}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    _mutate(() => sc.dialogue.add(Line()));
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加台词'),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < sc.dialogue.length; i++)
                  _storyRow(c, setSheet, sc, i, charNames, images),
                const Divider(height: 28),
                Row(
                  children: [
                    const Expanded(
                        child: Text('🔀 选项分支',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold))),
                    TextButton.icon(
                      onPressed: () {
                        _mutate(() => sc.choices.add(Choice()));
                        setSheet(() {});
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加选项'),
                    ),
                  ],
                ),
                if (sc.choices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('（无选项：台词结束后自动进入「下一场景」）',
                        style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ),
                for (var i = 0; i < sc.choices.length; i++)
                  _choiceRow(c, setSheet, sc, i),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _storyRow(BuildContext c, StateSetter setSheet, Scene sc, int i,
      List<String> charNames, List<String> images) {
    final ln = sc.dialogue[i];
    final spk = ln.speaker.isEmpty ? '（旁白）' : ln.speaker;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: const Color(0xFF2E2E36),
      child: InkWell(
        onTap: () => _editLineDialog(c, setSheet, sc, i, charNames, images),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              Text('#${i + 1}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spk,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.lightBlueAccent,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(ln.text.isEmpty ? '（空台词）' : ln.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    if (ln.cg.isNotEmpty)
                      Text('🖼 ${ln.cg}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
              _miniBtn(Icons.arrow_upward, () {
                _moveLine(sc, i, -1);
                setSheet(() {});
              }),
              _miniBtn(Icons.arrow_downward, () {
                _moveLine(sc, i, 1);
                setSheet(() {});
              }),
              _miniBtn(Icons.delete_outline, () {
                _delLine(sc, i);
                setSheet(() {});
              }, red: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap, {bool red = false}) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 17,
      icon: Icon(icon, color: red ? Colors.redAccent : Colors.white70),
      onPressed: onTap,
    );
  }

  Future<void> _editLineDialog(BuildContext c, StateSetter setSheet, Scene sc,
      int i, List<String> charNames, List<String> images) async {
    final ln = sc.dialogue[i];
    final textCtrl = TextEditingController(text: ln.text);
    String speaker = ln.speaker;
    String cg = ln.cg;
    await showDialog<void>(
      context: c,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setD) => AlertDialog(
          title: const Text('编辑台词'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dd('说话人（空=旁白）', charNames, speaker, (v) {
                  speaker = v ?? '';
                }, emptyLabel: '（旁白）',
                    extraValue: speaker, key: const ValueKey('d_spk')),
                TextField(
                  controller: textCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: '台词内容'),
                ),
                const SizedBox(height: 8),
                _dd('本句 CG（可选）', images, cg, (v) {
                  cg = v ?? '';
                }, extraValue: cg, key: const ValueKey('d_cg')),
                if (ln.cgHint.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('🖼 AI 建议 CG：${ln.cgHint}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dc),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                _mutate(() {
                  ln.speaker = speaker;
                  ln.text = textCtrl.text.trim();
                  ln.cg = cg;
                });
                setSheet(() {});
                Navigator.pop(dc);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow(BuildContext c, StateSetter setSheet, Scene sc, int i) {
    final ch = sc.choices[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: const Color(0xFF2E2E36),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.fork_right, size: 16, color: Colors.white38),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => _editChoiceDialog(c, setSheet, sc, i),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ch.text.isEmpty ? '（空选项）' : ch.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    Text(_nextLabel(ch.next),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
            ),
            _miniBtn(Icons.arrow_upward, () {
              _moveChoice(sc, i, -1);
              setSheet(() {});
            }),
            _miniBtn(Icons.arrow_downward, () {
              _moveChoice(sc, i, 1);
              setSheet(() {});
            }),
            _miniBtn(Icons.delete_outline, () {
              _delChoice(sc, i);
              setSheet(() {});
            }, red: true),
          ],
        ),
      ),
    );
  }

  String _nextLabel(String next) {
    if (next.isEmpty) return '→（结束）';
    final sc = _p!.script.findScene(next);
    return sc == null ? '→ $next' : '→ ${sc.name}';
  }

  Future<void> _editChoiceDialog(
      BuildContext? c, StateSetter? setSheet, Scene sc, int i,
      {bool allowDelete = false}) async {
    final ch = sc.choices[i];
    final textCtrl = TextEditingController(text: ch.text);
    String next = ch.next;
    final sceneIds = _p!.script.scenes.map((s) => s.id).toList();
    final ctx = c ?? context;
    await showDialog<void>(
      context: ctx,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setD) => AlertDialog(
          title: const Text('编辑选项'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: textCtrl,
                  decoration: const InputDecoration(labelText: '选项文字')),
              const SizedBox(height: 8),
              _dd('跳转到', sceneIds, next, (v) {
                next = v ?? '';
              }, showEnd: true,
                  extraValue: next, key: const ValueKey('d_next')),
            ],
          ),
          actions: [
            if (allowDelete)
              TextButton(
                style:
                    TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () {
                  _mutate(() {
                    sc.choices.removeAt(i);
                    if (_selLink?.sourceId == sc.id) _selLink = null;
                  });
                  setSheet?.call(() {});
                  Navigator.pop(dc);
                },
                child: const Text('删除'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(dc),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                _mutate(() {
                  ch.text = textCtrl.text.trim();
                  ch.next = next;
                });
                setSheet?.call(() {});
                Navigator.pop(dc);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑主线连接：换目标（下拉或画布点选）/ 删除
  Future<void> _editNextLinkDialog(Scene sc) async {
    final sceneIds = _p!.script.scenes.map((s) => s.id).toList();
    String next = sc.next;
    await showDialog<void>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setD) => AlertDialog(
          title: const Text('主线连接'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('从「${sc.name}」出发的主线',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 8),
              _dd('跳转到', sceneIds, next, (v) {
                next = v ?? '';
              }, showEnd: true,
                  extraValue: next, key: const ValueKey('d_next_link')),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dc);
                  _startRetarget(sc.id, -1);
                },
                icon: const Icon(Icons.touch_app, size: 18),
                label: const Text('在画布上点选目标'),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              onPressed: () {
                _mutate(() {
                  sc.next = '';
                  _selLink = null;
                });
                Navigator.pop(dc);
              },
              child: const Text('删除主线'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(dc),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                _mutate(() {
                  sc.next = next;
                  _selLink = null;
                });
                Navigator.pop(dc);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 连接管理面板：主线 + 所有选项分支的列表编辑
  void _manageLinks(Scene sc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF232329),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('🗂 连接管理',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(c)),
                  ],
                ),
                Text('节点：${sc.name}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                        child: Text('🔗 主线',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600))),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        _startRetarget(sc.id, -1);
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('设置主线'),
                    ),
                  ],
                ),
                if (sc.next.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('（未设置：台词播完自动结束）',
                        style:
                            TextStyle(fontSize: 12, color: Colors.white54)),
                  )
                else
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: const Color(0xFF2E2E36),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.arrow_forward,
                          size: 18, color: Color(0xFFFFC24B)),
                      title: Text(_nextLabel(sc.next),
                          style: const TextStyle(fontSize: 13)),
                      onTap: () {
                        Navigator.pop(c);
                        _editNextLinkDialog(sc);
                      },
                      trailing: _miniBtn(Icons.delete_outline, () {
                        _mutate(() {
                          sc.next = '';
                          _selLink = null;
                        });
                        setSheet(() {});
                      }, red: true),
                    ),
                  ),
                const Divider(height: 20),
                Row(
                  children: [
                    const Expanded(
                        child: Text('🔀 选项分支',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600))),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(c);
                        setState(() {
                          _clearModes();
                          _linkMode = true;
                          _linkKind = _LinkKind.choice;
                        });
                        _toast('🔀 选项分支模式：点起点节点');
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('添加选项'),
                    ),
                  ],
                ),
                if (sc.choices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('（无选项分支）',
                        style:
                            TextStyle(fontSize: 12, color: Colors.white54)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sc.choices.length,
                      itemBuilder: (c, i) => Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: const Color(0xFF2E2E36),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                          child: Row(
                            children: [
                              const Icon(Icons.fork_right,
                                  size: 16, color: Color(0xFFB07CD8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.pop(c);
                                    _editChoiceDialog(null, null, sc, i,
                                        allowDelete: true);
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          sc.choices[i].text.isEmpty
                                              ? '（空选项）'
                                              : sc.choices[i].text,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              const TextStyle(fontSize: 13)),
                                      Text(_nextLabel(sc.choices[i].next),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white38)),
                                    ],
                                  ),
                                ),
                              ),
                              _miniBtn(Icons.arrow_upward, () {
                                _moveChoice(sc, i, -1);
                                setSheet(() {});
                              }),
                              _miniBtn(Icons.arrow_downward, () {
                                _moveChoice(sc, i, 1);
                                setSheet(() {});
                              }),
                              _miniBtn(Icons.delete_outline, () {
                                _mutate(() {
                                  _delChoice(sc, i);
                                  if (_selLink?.sourceId == sc.id) {
                                    _selLink = null;
                                  }
                                });
                                setSheet(() {});
                              }, red: true),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- CG / BGM 素材面板 ----------
  void _editCgs(Scene sc) {
    _assetListSheet(sc, '🖼 CG 素材', sc.cgs, Icons.image_outlined,
        '还没有 CG，点下方按钮从资产添加', () => _addCgTo(sc));
  }

  void _editBgms(Scene sc) {
    _assetListSheet(sc, '🎵 BGM 素材', sc.bgms, Icons.music_note_outlined,
        '还没有 BGM，点下方按钮从资产添加', () => _addBgmTo(sc));
  }

  void _assetListSheet(Scene sc, String title, List<String> list,
      IconData icon, String emptyHint, VoidCallback add) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF232329),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(c)),
                  ],
                ),
                Text('节点：${sc.name}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: add,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(emptyHint,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (c, i) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(icon, size: 18),
                        title: Text(list[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _miniBtn(Icons.arrow_upward, () {
                              _moveStr(list, i, -1);
                              setSheet(() {});
                            }),
                            _miniBtn(Icons.arrow_downward, () {
                              _moveStr(list, i, 1);
                              setSheet(() {});
                            }),
                            _miniBtn(Icons.delete_outline, () {
                              _delStr(list, i);
                              setSheet(() {});
                            }, red: true),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  /// 通用下拉：空值显示 [emptyLabel]，可选 [extraValue] 保证当前值必在候选中
  /// [key] 用于在切换场景/行时强制重建 FormField 状态（initialValue 只在首次生效）
  Widget _dd(String label, List<String> values, String current,
      ValueChanged<String?> onChanged,
      {String emptyLabel = '（无）',
      bool showEnd = false,
      String? extraValue,
      Key? key}) {
    final items = <String>{''};
    items.addAll(values);
    if (showEnd) items.add('__END__');
    if (extraValue != null && extraValue.isNotEmpty) items.add(extraValue);
    if (current.isNotEmpty) items.add(current);
    final list = items.toList()..sort();
    String? value = current;
    if (current == '') value = '';
    if (current == '__END__') value = '__END__';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        key: key,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
        ),
        items: list.map((v) {
          String labelText;
          if (v == '') {
            labelText = emptyLabel;
          } else if (v == '__END__') {
            labelText = '（结束 — 完）';
          } else if (v.startsWith('s') && _p!.script.indexOfScene(v) >= 0) {
            labelText = '${_p!.script.findScene(v)!.name}（$v）';
          } else {
            labelText = v;
          }
          return DropdownMenuItem<String>(
              value: v, child: Text(labelText, overflow: TextOverflow.ellipsis));
        }).toList(),
        onChanged: (v) => onChanged(v == '__END__' ? '' : v),
      ),
    );
  }

  // ---------------- 资产 Tab ----------------
  Widget _buildAssetsTab() {
    final images = _assets.where((f) => ExportService.isImage(f.path)).toList();
    final bgms = _assets.where((f) => ExportService.isAudio(f.path)).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pickAssets(ExportService.imageExts),
                icon: const Icon(Icons.image_outlined),
                label: const Text('添加图片（CG/背景）'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _pickAssets(ExportService.audioExts),
                icon: const Icon(Icons.music_note_outlined),
                label: const Text('添加音乐（BGM）'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('图片（可作为背景 / 台词 CG）',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (images.isEmpty)
          const Text('还没有图片', style: TextStyle(color: Colors.white38))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in images)
                SizedBox(
                  width: 110,
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(f.path),
                                height: 110,
                                width: 110,
                                fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => _deleteAsset(f),
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                padding: const EdgeInsets.all(3),
                                child: const Icon(Icons.close,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(_name(f),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        const Divider(height: 28),
        const Text('音乐（可作为场景 BGM）',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (bgms.isEmpty)
          const Text('还没有音乐', style: TextStyle(color: Colors.white38))
        else
          for (final f in bgms)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: IconButton(
                  icon: Icon(_isPlaying(f.path)
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline),
                  onPressed: () => _togglePreview(f.path),
                ),
                title: Text(_name(f), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${(awaitSize(f) / 1024).round()} KB',
                    style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _deleteAsset(f),
                ),
              ),
            ),
        const SizedBox(height: 24),
      ],
    );
  }

  int awaitSize(File f) {
    try {
      return f.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  bool _isPlaying(String path) =>
      _preview != null && _previewCurrent == path;

  String? _previewCurrent;

  Future<void> _togglePreview(String path) async {
    if (_previewCurrent == path) {
      await _preview?.stop();
      _previewCurrent = null;
    } else {
      _preview?.dispose();
      final p = AudioPlayer();
      _preview = p;
      _previewCurrent = path;
      await p.play(DeviceFileSource(path));
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickAssets(List<String> exts) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: exts,
      allowMultiple: true,
    );
    if (res == null || _p == null) return;
    for (final f in res.files) {
      final path = f.path;
      if (path == null) continue;
      await Storage.copyIntoAssets(_p!.id, path, f.name);
    }
    await _refreshAssets();
  }

  Future<void> _deleteAsset(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除素材'),
        content: Text('删除 ${_name(f)}？引用它的场景将不再显示。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await f.delete();
    await _refreshAssets();
  }

  // ---------------- 导出 Tab ----------------
  Widget _buildExportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📦 导出项目包（agent 可加工格式）',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                const Text(
                    '导出为 zip：\n'
                    '• project.json — 完整剧情/角色/素材清单（纯文本，任何 AI agent 可直接解析与修改）\n'
                    '• assets/ — 图片与音乐原文件\n'
                    '• README.md — 格式说明与 agent 加工指引\n\n'
                    'agent 拿到后可按指引生成完整游戏工程（推荐 Ren'
                    "'"
                    'Py 引擎，支持安卓打包），也可继续增删场景、改分支、换 BGM/CG。',
                    style: TextStyle(fontSize: 13, height: 1.5)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share),
                  label: Text(_busy ? '打包中…' : '导出并分享'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🤖 一键生成剧本',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 10),
                Text(
                    '在「剧本」页点右上角 ✨ 按钮：输入主题 → AI 自动安排全部流程'
                    '（场景/台词/分支/BGM 与 CG 提示），生成后可逐项自由编辑。\n'
                    '需要先在首页 ⚙ 设置里填入 DeepSeek API 密钥；'
                    '未配置密钥时会生成可编辑的示例剧本。',
                    style: TextStyle(fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('▶ 试玩',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 10),
                Text(
                    '在「剧本」页点右上角 ▶ 按钮：内嵌播放器，支持 BGM 循环/音量、'
                    'CG 立绘、分支选择、快进、对话履历、自动存档续玩。',
                    style: TextStyle(fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================ AI 对话框
class AiDialog extends StatefulWidget {
  const AiDialog({super.key});
  @override
  State<AiDialog> createState() => _AiDialogState();
}

class _AiDialogState extends State<AiDialog> {
  final _premise = TextEditingController();
  String _genre = '日常';
  String _length = '中';
  final _tone = TextEditingController();
  bool _busy = false;
  String? _error;

  static const genres = ['日常', '恋爱', '悬疑', '科幻', '奇幻', '恐怖', '治愈'];
  static const lengths = ['短（3~5 场景）', '中（5~8 场景）', '长（8~12 场景）'];

  @override
  void dispose() {
    _premise.dispose();
    _tone.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final len = _length.startsWith('短') ? '短' : (_length.startsWith('长') ? '长' : '中');
      final r = await AiService.generate(
        premise: _premise.text,
        genre: _genre,
        length: len,
        tone: _tone.text.trim().isEmpty ? '轻松温暖' : _tone.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, {'script': r.script, 'demo': r.demo});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('🤖 AI 生成剧本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _premise,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '主题 / 背景设定',
                hintText: '例如：与青梅竹马在夏日祭的告白，但祭典背后藏着秘密……',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _genre,
              decoration: const InputDecoration(labelText: '类型', isDense: true),
              items: genres
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _genre = v ?? '日常'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _length,
              decoration: const InputDecoration(labelText: '篇幅', isDense: true),
              items: lengths
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _length = v ?? _length),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tone,
              decoration:
                  const InputDecoration(labelText: '氛围 / 文风（可选）'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
          onPressed: _busy ? null : _go,
          child: Text(_busy ? '生成中…' : '生成'),
        ),
      ],
    );
  }
}

// ================================================================ 设置
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  bool _hasKey = false;
  String _keyHint = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AiService.loadSettings();
    if (!mounted) return;
    _endpoint.text = s.endpoint;
    _model.text = s.model;
    _hasKey = s.apiKey.isNotEmpty;
    _keyHint = _hasKey ? '已保存密钥（…${s.apiKey.substring(s.apiKey.length - 4)}）' : '';
    setState(() {});
  }

  Future<void> _save() async {
    final s = await AiService.loadSettings();
    s.endpoint = _endpoint.text.trim().isEmpty ? s.endpoint : _endpoint.text.trim();
    s.model = _model.text.trim().isEmpty ? s.model : _model.text.trim();
    if (_key.text.trim().isNotEmpty) s.apiKey = _key.text.trim();
    await AiService.saveSettings(s);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 设置已保存')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              '用于「AI 生成剧本」的模型接口（OpenAI 兼容）。\n默认 DeepSeek：在 https://platform.deepseek.com 创建 API Key 填入下方即可。',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white70)),
          const SizedBox(height: 16),
          TextField(
            controller: _endpoint,
            decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://api.deepseek.com/v1/chat/completions'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
                labelText: '模型名', hintText: 'deepseek-v4-flash'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: true,
            decoration: InputDecoration(
                labelText: 'API Key',
                hintText: _hasKey ? '（$_keyHint，留空则保持不变）' : 'sk-…'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}

// ================================================================ 播放器
class PlayerScreen extends StatefulWidget {
  final Project project;
  const PlayerScreen({super.key, required this.project});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late Project _proj;
  late AudioPlayer _bgm;
  Map<String, String> _assetPaths = {};
  String? _sceneId;
  int _idx = 0;
  bool _started = false;
  bool _end = false;
  String _curBgm = '';
  final List<Map<String, String>> _backlog = [];
  Timer? _skip;

  @override
  void initState() {
    super.initState();
    _proj = widget.project;
    _bgm = AudioPlayer();
    _loadAssets();
  }

  @override
  void dispose() {
    _skip?.cancel();
    _bgm.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    final files = await Storage.listAssets(_proj.id);
    final m = <String, String>{};
    for (final f in files) {
      m[f.path.split(Platform.pathSeparator).last] = f.path;
    }
    if (mounted) setState(() => _assetPaths = m);
  }

  Scene? get _scene {
    final id = _sceneId;
    if (id == null) return null;
    return _proj.script.findScene(id);
  }

  bool get _inChoices {
    final sc = _scene;
    if (sc == null) return false;
    return _idx >= sc.dialogue.length && sc.choices.isNotEmpty;
  }

  Line? get _curLine {
    final sc = _scene;
    if (sc == null || _idx >= sc.dialogue.length) return null;
    return sc.dialogue[_idx];
  }

  Color? _charColor(String name) {
    for (final c in _proj.characters) {
      if (c.name == name) return parseColor(c.color);
    }
    return null;
  }

  // ---------- 流程 ----------
  Future<void> _start(bool cont) async {
    if (cont) {
      final save = await Storage.loadSave(_proj.id);
      if (save != null) {
        final sid = save['scene'] as String?;
        if (sid != null && _proj.script.findScene(sid) != null) {
          _sceneId = sid;
          _idx = (save['idx'] as num?)?.toInt() ?? 0;
        }
      }
    }
    final sid0 = _sceneId;
    if (sid0 == null || _proj.script.findScene(sid0) == null) {
      _sceneId = _proj.script.start.isNotEmpty
          ? _proj.script.start
          : _proj.script.scenes.first.id;
      _idx = 0;
    }
    if (!mounted) return;
    setState(() {
      _started = true;
      _end = false;
      _backlog.clear();
    });
    await _applyScene();
  }

  Future<void> _applyScene() async {
    final sc = _scene;
    if (sc == null) {
      _endGame();
      return;
    }
    final bgmName = sc.bgm.isNotEmpty
        ? sc.bgm
        : (sc.bgms.isNotEmpty ? sc.bgms.first : '');
    if (bgmName != _curBgm) {
      _curBgm = bgmName;
      await _bgm.stop();
      final path = _assetPaths[bgmName];
      if (bgmName.isNotEmpty && path != null) {
        await _bgm.setVolume(sc.bgmVolume.clamp(0.0, 1.0));
        await _bgm.setReleaseMode(ReleaseMode.loop);
        await _bgm.play(DeviceFileSource(path));
      }
    } else {
      await _bgm.setVolume(sc.bgmVolume.clamp(0.0, 1.0));
    }
    if (mounted) setState(() {});
  }

  void _advance() {
    final sc = _scene;
    if (sc == null) return;
    if (_idx < sc.dialogue.length) {
      _backlog.add({
        'speaker': sc.dialogue[_idx].speaker,
        'text': sc.dialogue[_idx].text,
      });
      if (_backlog.length > 500) _backlog.removeAt(0);
      _idx++;
    }
    if (_idx >= sc.dialogue.length) {
      if (sc.choices.isNotEmpty) {
        // 等待选择
      } else if (sc.next.isNotEmpty) {
        _sceneId = sc.next;
        _idx = 0;
        _applyScene();
        return;
      } else {
        _endGame();
        return;
      }
    }
    _saveGame();
    if (mounted) setState(() {});
  }

  void _choose(int i) {
    final sc = _scene;
    if (sc == null || i < 0 || i >= sc.choices.length) return;
    final next = sc.choices[i].next;
    if (next.isNotEmpty && _proj.script.findScene(next) != null) {
      _sceneId = next;
      _idx = 0;
      _applyScene();
    } else {
      _endGame();
    }
  }

  void _endGame() {
    _bgm.stop();
    if (mounted) {
      setState(() {
        _end = true;
        _curBgm = '';
      });
    }
  }

  Future<void> _saveGame() async {
    final id = _sceneId;
    if (id == null) return;
    await Storage.saveGame(_proj.id, id, _idx);
  }

  void _toggleSkip() {
    if (_skip != null) {
      _skip!.cancel();
      _skip = null;
    } else {
      _skip = Timer.periodic(const Duration(milliseconds: 130), (_) {
        if (_end || !_started) {
          _skip!.cancel();
          _skip = null;
          return;
        }
        _advance();
      });
    }
    if (mounted) setState(() {});
  }

  void _showBacklogSheet() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SizedBox(
        height: 320,
        child: _backlog.isEmpty
            ? const Center(child: Text('暂无对话记录'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final e in _backlog.reversed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text.rich(TextSpan(children: [
                        if ((e['speaker'] ?? '').isNotEmpty)
                          TextSpan(
                              text: '${e['speaker']}：',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _charColor(e['speaker']!) ??
                                      Colors.white)),
                        TextSpan(text: e['text'] ?? ''),
                      ])),
                    ),
                ],
              ),
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final sc = _scene;
    final line = _curLine;
    final bgPath = sc != null && _assetPaths.containsKey(sc.bg)
        ? _assetPaths[sc.bg]
        : null;
    final cgPath =
        line != null && _assetPaths.containsKey(line.cg) ? _assetPaths[line.cg] : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 背景
          Positioned.fill(
            child: bgPath != null
                ? Image.file(File(bgPath), fit: BoxFit.cover)
                : Container(color: const Color(0xFF101426)),
          ),
          // CG 立绘
          if (_started && !_end && cgPath != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 160,
              child: Image.file(File(cgPath), fit: BoxFit.contain),
            ),
          // 台词框 + 选项
          if (_started && !_end && sc != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xEE0B0E1A)],
                  ),
                ),
                child: _inChoices
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < sc.choices.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white12,
                                    foregroundColor: Colors.white),
                                onPressed: () => _choose(i),
                                child: Text(sc.choices[i].text.isEmpty
                                    ? '（空选项）'
                                    : sc.choices[i].text),
                              ),
                            ),
                        ],
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _advance,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((line?.speaker ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  line!.speaker,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: _charColor(line.speaker) ??
                                        const Color(0xFFFF7AB8),
                                  ),
                                ),
                              ),
                            Text(
                              line?.text ?? '',
                              style: const TextStyle(
                                  fontSize: 16, height: 1.5, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.centerRight,
                              child: Text('▼',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.white38)),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          // 结束画面
          if (_started && _end)
            Positioned.fill(
              child: Container(
                color: const Color(0xCC0B0E1A),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('— 完 —',
                          style: TextStyle(
                              fontSize: 28, letterSpacing: 8, color: Colors.white)),
                      const SizedBox(height: 24),
                      FilledButton(
                          onPressed: () => _start(false),
                          child: const Text('↻ 重新开始')),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回')),
                    ],
                  ),
                ),
              ),
            ),
          // 开始画面
          if (!_started)
            Positioned.fill(
              child: Container(
                color: const Color(0xF20B0E1A),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_proj.script.title.isEmpty
                            ? _proj.title
                            : _proj.script.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        if (_proj.script.summary.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_proj.script.summary,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.white70)),
                          ),
                        const SizedBox(height: 32),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(200, 48)),
                          onPressed: () => _start(false),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('开始游戏'),
                        ),
                        const SizedBox(height: 10),
                        FutureBuilder<Map<String, dynamic>?>(
                          future: Storage.loadSave(_proj.id),
                          builder: (c, snap) {
                            if (snap.data == null) return const SizedBox.shrink();
                            return OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(200, 48)),
                              onPressed: () => _start(true),
                              icon: const Icon(Icons.history),
                              label: const Text('继续游戏'),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('返回')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 顶栏
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.history, color: Colors.white70),
                    tooltip: '对话履历',
                    onPressed: _showBacklogSheet,
                  ),
                  IconButton(
                    icon: Icon(
                      _skip != null
                          ? Icons.fast_forward
                          : Icons.fast_forward_outlined,
                      color: Colors.white70,
                    ),
                    tooltip: '快进',
                    onPressed: _toggleSkip,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画布背景点阵
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    const gap = 26.0;
    for (var x = 8.0; x < size.width; x += gap) {
      for (var y = 8.0; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) => false;
}

/// 连接工具栏动作
enum _LinkAction { next, choice, manage }

/// 串联模式类型：主线（next）或选项分支（choices）
enum _LinkKind { next, choice }

/// 画布连线标识（用于选中高亮）
class _LinkKey {
  final String sourceId;
  final bool isChoice; // true=选项分支，false=主线 next
  final int index; // 选项下标（主线恒为 0）
  const _LinkKey(this.sourceId, this.isChoice, this.index);

  @override
  bool operator ==(Object o) =>
      o is _LinkKey &&
      o.sourceId == sourceId &&
      o.isChoice == isChoice &&
      o.index == index;

  @override
  int get hashCode => Object.hash(sourceId, isChoice, index);
}

/// 画布重设目标模式：choiceIndex=-1 表示主线 next
class _Retarget {
  final String sourceId;
  final int choiceIndex;
  const _Retarget(this.sourceId, this.choiceIndex);
}

/// 生成节点间连线路径（绘制与命中检测共用）
Path linkPath(Offset a, Offset b) {
  final dir = b - a;
  final len = dir.distance;
  if (len < 40) return Path();
  final u = dir / len;
  final start = a + u * 82;
  final end = b - u * 82;
  final mid = (start + end) / 2 + const Offset(0, -24);
  return Path()
    ..moveTo(start.dx, start.dy)
    ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
}

/// 场景串联连线：next 主线（金色）+ choices 分支（紫色虚线，带选项文字标签）；选中连线高亮白色
class _LinkPainter extends CustomPainter {
  final List<Scene> scenes;
  final List<Offset> centers;
  final _LinkKey? selected;
  const _LinkPainter(this.scenes, this.centers, this.selected);

  Offset _centerOf(Scene sc) {
    final i = scenes.indexOf(sc);
    if (i < 0 || i >= centers.length) return Offset.zero;
    return centers[i];
  }

  @override
  void paint(Canvas canvas, Size size) {
    Scene? targetOf(String id) {
      for (final s in scenes) {
        if (s.id == id) return s;
      }
      return null;
    }

    for (final sc in scenes) {
      final a = _centerOf(sc);
      // next 主线：金色实线箭头
      if (sc.next.isNotEmpty) {
        final t = targetOf(sc.next);
        if (t != null) {
          final sel = selected == _LinkKey(sc.id, false, 0);
          _arrow(canvas, a, _centerOf(t),
              sel ? const Color(0xFFFFFFFF) : const Color(0xFFFFC24B),
              sel ? 4.5 : 2.5);
        }
      }
      // choices 分支：紫色虚线箭头 + 选项文字标签
      for (var i = 0; i < sc.choices.length; i++) {
        final ch = sc.choices[i];
        if (ch.next.isEmpty) continue;
        final t = targetOf(ch.next);
        if (t == null) continue;
        final sel = selected == _LinkKey(sc.id, true, i);
        _arrow(canvas, a, _centerOf(t),
            sel ? const Color(0xFFFFFFFF) : const Color(0xFFB07CD8),
            sel ? 3.5 : 2.0,
            dashed: true);
        if (ch.text.trim().isNotEmpty) {
          _label(canvas, a, _centerOf(t), ch.text.trim(), sel);
        }
      }
    }
  }

  void _label(Canvas canvas, Offset a, Offset b, String text, bool sel) {
    final metrics = linkPath(a, b).computeMetrics().toList();
    if (metrics.isEmpty) return;
    final tangent = metrics.first.getTangentForOffset(metrics.first.length / 2);
    if (tangent == null) return;
    final pos = tangent.position + const Offset(0, -30);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          color: Colors.white,
          backgroundColor:
              sel ? const Color(0xCC5555FF) : const Color(0xCC5A2E7A),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _arrow(Canvas canvas, Offset a, Offset b, Color color, double width,
      {bool dashed = false}) {
    if (a == Offset.zero || b == Offset.zero) return;
    final dir = b - a;
    final len = dir.distance;
    if (len < 40) return;
    final u = dir / len;
    final path = linkPath(a, b);
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    if (dashed) {
      _drawDashedPath(canvas, path, paint);
    } else {
      canvas.drawPath(path, paint);
    }
    // 箭头
    final end = b - u * 82;
    final tip = end - u * 10;
    final arrow = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - u.dx * 12 + u.dy * 6, tip.dy - u.dy * 12 - u.dx * 6)
      ..lineTo(tip.dx - u.dx * 12 - u.dy * 6, tip.dy - u.dy * 12 + u.dx * 6)
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      const dash = 10.0;
      const gap = 7.0;
      while (dist < metric.length) {
        final end = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinkPainter oldDelegate) =>
      oldDelegate.scenes != scenes ||
      oldDelegate.centers != centers ||
      oldDelegate.selected != selected;
}
