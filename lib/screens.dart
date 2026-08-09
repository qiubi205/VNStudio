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

/// 带外部值同步的文本框：用 controller 承载 initialValue，key 变化时重建
/// （切换场景/行时表单值强制刷新，打字时不丢光标）
class _SyncField extends StatefulWidget {
  const _SyncField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final int minLines;
  final int maxLines;

  @override
  State<_SyncField> createState() => _SyncFieldState();
}

class _SyncFieldState extends State<_SyncField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_SyncField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text && !_c.selection.isValid) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        decoration: widget.decoration,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        onChanged: widget.onChanged,
      );
}

class _EditorScreenState extends State<EditorScreen> {
  Project? _p;
  List<File> _assets = [];
  int _tab = 0;
  String? _sel;
  bool _busy = false;
  AudioPlayer? _preview;
  /// 表单版本号：剧本整体替换（新建/AI 应用/加载）时自增，强制重建编辑器表单
  int _formEpoch = 0;

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
      _formEpoch++;
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

  // ---------- 剧本操作 ----------
  void _setScene(String field, dynamic v) {
    final sc = _current();
    if (sc == null) return;
    _mutate(() {
      switch (field) {
        case 'name': sc.name = v as String;
        case 'bg': sc.bg = v as String;
        case 'bgm': sc.bgm = v as String;
        case 'bgm_volume': sc.bgmVolume = (v as num).toDouble();
        case 'next': sc.next = v as String;
      }
    });
  }

  void _setLine(int i, String field, dynamic v) {
    final sc = _current();
    if (sc == null || i < 0 || i >= sc.dialogue.length) return;
    final ln = sc.dialogue[i];
    _mutate(() {
      switch (field) {
        case 'speaker': ln.speaker = v as String;
        case 'text': ln.text = v as String;
        case 'cg': ln.cg = v as String;
      }
    });
  }

  void _setChoice(int i, String field, dynamic v) {
    final sc = _current();
    if (sc == null || i < 0 || i >= sc.choices.length) return;
    final ch = sc.choices[i];
    _mutate(() {
      switch (field) {
        case 'text': ch.text = v as String;
        case 'next': ch.next = v as String;
      }
    });
  }

  void _addScene() {
    final p = _p;
    if (p == null) return;
    var n = 1;
    final ids = p.script.scenes.map((s) => s.id).toSet();
    while (ids.contains('s$n')) {
      n++;
    }
    final sc = Scene(id: 's$n', name: '场景 $n', dialogue: [Line()]);
    _mutate(() {
      p.script.scenes.add(sc);
      _sel = sc.id;
    });
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

  void _moveScene(int dir) {
    final p = _p;
    if (p == null || _sel == null) return;
    final i = p.script.indexOfScene(_sel!);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= p.script.scenes.length) return;
    _mutate(() {
      final t = p.script.scenes[i];
      p.script.scenes[i] = p.script.scenes[j];
      p.script.scenes[j] = t;
    });
  }

  void _addLine() {
    final sc = _current();
    if (sc == null) return;
    _mutate(() => sc.dialogue.add(Line()));
  }

  void _delLine(int i) {
    final sc = _current();
    if (sc == null || i < 0 || i >= sc.dialogue.length) return;
    _mutate(() => sc.dialogue.removeAt(i));
  }

  void _moveLine(int i, int dir) {
    final sc = _current();
    if (sc == null) return;
    final j = i + dir;
    if (i < 0 || j < 0 || j >= sc.dialogue.length) return;
    _mutate(() {
      final t = sc.dialogue[i];
      sc.dialogue[i] = sc.dialogue[j];
      sc.dialogue[j] = t;
    });
  }

  void _addChoice() {
    final sc = _current();
    if (sc == null) return;
    _mutate(() => sc.choices.add(Choice()));
  }

  void _delChoice(int i) {
    final sc = _current();
    if (sc == null || i < 0 || i >= sc.choices.length) return;
    _mutate(() => sc.choices.removeAt(i));
  }

  void _moveChoice(int i, int dir) {
    final sc = _current();
    if (sc == null) return;
    final j = i + dir;
    if (i < 0 || j < 0 || j >= sc.choices.length) return;
    _mutate(() {
      final t = sc.choices[i];
      sc.choices[i] = sc.choices[j];
      sc.choices[j] = t;
    });
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
      _formEpoch++;
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
    return Scaffold(
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
              children: [_buildScriptTab(), _buildAssetsTab(), _buildExportTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- 剧本 Tab ----------------
  Widget _buildScriptTab() {
    final p = _p!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 148,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    const Expanded(
                        child: Text('场景',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      tooltip: '添加场景',
                      onPressed: _addScene,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: p.script.scenes.length,
                  itemBuilder: (c, i) {
                    final sc = p.script.scenes[i];
                    final active = sc.id == _sel;
                    return Card(
                      color: active ? Colors.indigo.shade800 : null,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: InkWell(
                        onTap: () => setState(() => _sel = sc.id),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sc.name.isEmpty ? sc.id : sc.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13)),
                              Text(
                                  '${sc.dialogue.length} 句 · ${sc.choices.length} 选项',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white54)),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 16,
                                      icon: const Icon(Icons.arrow_upward),
                                      onPressed: () => _moveScene(-1)),
                                  IconButton(
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 16,
                                      icon: const Icon(Icons.arrow_downward),
                                      onPressed: () => _moveScene(1)),
                                  IconButton(
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 16,
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.redAccent),
                                      onPressed: _delScene),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.white12),
        Expanded(child: _buildScenePanel()),
      ],
    );
  }

  Widget _buildScenePanel() {
    final sc = _current();
    if (sc == null) {
      return const Center(
          child: Text('没有场景，点左侧 ＋ 添加',
              style: TextStyle(color: Colors.white54)));
    }
    final images = _imageNames();
    final bgms = _bgmNames();
    final p = _p!;
    return ListView(
      key: ValueKey('scene_form_$_formEpoch'),
      padding: const EdgeInsets.all(12),
      children: [
        _SyncField(
          decoration: const InputDecoration(labelText: '作品标题'),
          value: p.title,
          onChanged: _setTitle,
        ),
        const SizedBox(height: 8),
        _SyncField(
          decoration: const InputDecoration(labelText: '简介'),
          value: p.script.summary,
          onChanged: _setSummary,
        ),
        const Divider(height: 24),
        _SyncField(
          key: ValueKey('sc_${sc.id}_name'),
          decoration: const InputDecoration(labelText: '场景名称'),
          value: sc.name,
          onChanged: (v) => _setScene('name', v),
        ),
        _dd('背景画面（图片）', images, sc.bg, (v) => _setScene('bg', v ?? ''),
            key: ValueKey('sc_${sc.id}_bg')),
        if (sc.bgHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('🎨 AI 建议背景：${sc.bgHint}',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ),
        _dd('BGM（音乐）', bgms, sc.bgm, (v) => _setScene('bgm', v ?? ''),
            key: ValueKey('sc_${sc.id}_bgm')),
        if (sc.bgmHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('🎵 AI 建议 BGM：${sc.bgmHint}',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ),
        Row(
          children: [
            const Text('BGM 音量', style: TextStyle(fontSize: 13)),
            Expanded(
              child: Slider(
                value: sc.bgmVolume.clamp(0.0, 1.0),
                onChanged: (v) => _setScene('bgm_volume', v),
              ),
            ),
            Text('${(sc.bgmVolume * 100).round()}%',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
        const Divider(height: 24),
        Row(
          children: [
            const Expanded(
                child: Text('台词',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            TextButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加台词'),
            ),
          ],
        ),
        for (var i = 0; i < sc.dialogue.length; i++) _lineCard(sc, i, images),
        const Divider(height: 24),
        Row(
          children: [
            const Expanded(
                child: Text('选项分支',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            TextButton.icon(
              onPressed: _addChoice,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加选项'),
            ),
          ],
        ),
        if (sc.choices.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('（无选项，台词结束后将自动进入「下一场景」）',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ),
        for (var i = 0; i < sc.choices.length; i++) _choiceCard(sc, i),
        const Divider(height: 24),
        const Text('台词结束后的走向',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        _dd('下一场景', p.script.scenes.map((s) => s.id).toList(), sc.next,
            (v) => _setScene('next', v ?? ''),
            showEnd: true, key: ValueKey('sc_${sc.id}_next')),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _lineCard(Scene sc, int i, List<String> images) {
    final ln = sc.dialogue[i];
    final p = _p!;
    final charNames = p.characters.map((c) => c.name).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${i + 1}',
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
                const SizedBox(width: 8),
                Expanded(
                  child: _dd('说话人（空=旁白）', charNames, ln.speaker,
                      (v) => _setLine(i, 'speaker', v ?? ''),
                      emptyLabel: '（旁白）', extraValue: ln.speaker,
                      key: ValueKey('sc_${sc.id}_spk_$i')),
                ),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: () => _moveLine(i, -1)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: () => _moveLine(i, 1)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    onPressed: () => _delLine(i)),
              ],
            ),
            _dd('本句 CG（可选）', images, ln.cg,
                (v) => _setLine(i, 'cg', v ?? ''),
                key: ValueKey('sc_${sc.id}_cg_$i')),
            _SyncField(
              key: ValueKey('sc_${sc.id}_ln_$i'),
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(hintText: '台词内容……'),
              value: ln.text,
              onChanged: (v) => _setLine(i, 'text', v),
            ),
            if (ln.cgHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('🖼 AI 建议 CG：${ln.cgHint}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _choiceCard(Scene sc, int i) {
    final ch = sc.choices[i];
    final p = _p!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('选项',
                    style: TextStyle(fontSize: 12, color: Colors.white38)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: () => _moveChoice(i, -1)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: () => _moveChoice(i, 1)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    onPressed: () => _delChoice(i)),
              ],
            ),
            _SyncField(
              key: ValueKey('sc_${sc.id}_ch_$i'),
              decoration: const InputDecoration(hintText: '选项文字'),
              value: ch.text,
              onChanged: (v) => _setChoice(i, 'text', v),
            ),
            _dd('跳转到', p.script.scenes.map((s) => s.id).toList(), ch.next,
                (v) => _setChoice(i, 'next', v ?? ''), showEnd: true,
                key: ValueKey('sc_${sc.id}_jump_$i')),
          ],
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
    final res = await FilePicker.pickFiles(
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
    if (sc.bgm != _curBgm) {
      _curBgm = sc.bgm;
      await _bgm.stop();
      final path = _assetPaths[sc.bgm];
      if (sc.bgm.isNotEmpty && path != null) {
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