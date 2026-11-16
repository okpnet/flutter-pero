import '../model/model.dart';

/// 整合性確認で行った修復の記録(9.4-5)。
class Repairs {
  final List<String> items = [];
  void add(String s) => items.add(s);
  int get count => items.length;
  bool get isEmpty => items.isEmpty;
  void addAll(Repairs o) => items.addAll(o.items);

  /// 件数と概要。
  String summary({int maxLines = 20}) {
    final shown = items.take(maxLines).join('\n');
    final rest = items.length > maxLines ? '\n…ほか${items.length - maxLines}件' : '';
    return '修復 $count件\n$shown$rest';
  }
}

/// モデル内部の整合性確認と修復(9.4-3の参照切れ、ID重複、型の不足)。
class IntegrityRepairer {
  /// 1回分の検査と修復。修復があれば [Repairs] に記録する。
  static Repairs repairOnce(ErModel m) {
    final rep = Repairs();
    _repairTypes(m, rep);
    _repairIds(m, rep);
    _repairShared(m, rep);
    _repairEntities(m, rep);
    _repairRelationships(m, rep);
    _repairDiagrams(m, rep);
    return rep;
  }

  /// 修復して再検査する(最大3回)。残りがあるときは false。
  static (bool, Repairs) repairAll(ErModel m) {
    final total = Repairs();
    for (var i = 0; i < 3; i++) {
      final r = repairOnce(m);
      if (r.isEmpty) return (true, total);
      total.addAll(r);
    }
    // 3回修復した後の確認
    final last = repairOnce(m);
    total.addAll(last);
    return (last.isEmpty, total);
  }

  static void _repairTypes(ErModel m, Repairs rep) {
    final seen = <String>{};
    m.types.removeWhere((t) {
      if (!seen.add(t.id)) {
        rep.add('型IDの重複を削除: ${t.id}');
        return true;
      }
      return false;
    });
    for (final s in standardTypes()) {
      if (!seen.contains(s.id)) {
        m.types.add(s);
        rep.add('標準型を補完: ${s.id}');
      }
    }
  }

  static void _repairIds(ErModel m, Repairs rep) {
    final used = <int>{};
    var maxId = 0;
    bool take(int id, String what) {
      if (id <= 0 || !used.add(id)) {
        rep.add('IDの重複または不正により$whatを削除: $id');
        return false;
      }
      if (id > maxId) maxId = id;
      return true;
    }

    m.methods.removeWhere((x) => !take(x.id, 'メソッド'));
    m.patterns.removeWhere((p) {
      if (!take(p.id, '共通列パターン')) return true;
      p.columns.removeWhere((c) => !take(c.id, '共通列'));
      return false;
    });
    m.entities.removeWhere((e) {
      if (!take(e.id, 'エンティティ')) return true;
      if (e is TableEntity) {
        e.columns.removeWhere((c) => !take(c.id, '列'));
        e.indexes.removeWhere((c) => !take(c.id, 'インデックス'));
        e.uniques.removeWhere((c) => !take(c.id, 'ユニーク'));
        e.checks.removeWhere((c) => !take(c.id, 'CHECK制約'));
        e.triggers.removeWhere((c) => !take(c.id, 'トリガー'));
      }
      return false;
    });
    m.relationships.removeWhere((r) => !take(r.id, 'リレーションシップ'));
    m.diagrams.removeWhere((d) => !take(d.id, 'ダイアグラム'));
    if (m.nextId <= maxId) {
      rep.add('nextIdを${maxId + 1}に修正');
      m.nextId = maxId + 1;
    }
  }

  static void _repairShared(ErModel m, Repairs rep) {
    final typeIds = m.types.map((t) => t.id).toSet();
    final methodIds = m.methods.map((x) => x.id).toSet();
    for (final p in m.patterns) {
      p.columns.removeWhere((c) {
        if (!typeIds.contains(c.typeId)) {
          rep.add('共通列 ${c.physicalName} の型が存在しないため削除');
          return true;
        }
        return false;
      });
      for (final c in p.columns) {
        if (c.pk) {
          c.pk = false;
          rep.add('共通列 ${c.physicalName} のPKを解除');
        }
        _fixDefault(c, methodIds, rep);
      }
    }
    final tableIds = m.entities.map((e) => e.id).toSet();
    for (final x in m.methods) {
      final before = x.dependsOnTableIds.length;
      x.dependsOnTableIds.removeWhere((id) => !tableIds.contains(id));
      if (x.dependsOnTableIds.length != before) {
        rep.add('メソッド ${x.name} の存在しない依存テーブルを削除');
      }
    }
  }

  static void _fixDefault(ColumnDef c, Set<int> methodIds, Repairs rep) {
    if (c.defaultMethodId != null && !methodIds.contains(c.defaultMethodId)) {
      rep.add('列 ${c.physicalName} のデフォルトメソッドが存在しないため解除');
      c.defaultMethodId = null;
      if (c.defaultKind == DefaultKind.method) c.defaultKind = DefaultKind.none;
    }
    if (c.defaultKind == DefaultKind.method && c.defaultMethodId == null) {
      c.defaultKind = DefaultKind.none;
    }
  }

  static void _repairEntities(ErModel m, Repairs rep) {
    final typeIds = m.types.map((t) => t.id).toSet();
    final methodIds = m.methods.map((x) => x.id).toSet();
    final tableIds = m.tables.map((t) => t.id).toSet();

    for (final t in m.tables) {
      t.columns.removeWhere((c) {
        if (!typeIds.contains(c.typeId)) {
          rep.add('テーブル ${t.physicalName} の列 ${c.physicalName} の型が存在しないため削除');
          return true;
        }
        return false;
      });
      for (final c in t.columns) {
        if (c.pk && !c.notNull) c.notNull = true;
        _fixDefault(c, methodIds, rep);
      }
      bool valid(int id) => t.columnById(id) != null || m.patternColumnById(id) != null;
      for (final list in [t.indexes, t.uniques]) {
        for (final c in list) {
          final before = c.columnIds.length;
          c.columnIds.removeWhere((id) => !valid(id));
          if (c.columnIds.length != before) {
            rep.add('テーブル ${t.physicalName} の制約の存在しない列参照を削除');
          }
        }
        list.removeWhere((c) {
          if (c.columnIds.isEmpty) {
            rep.add('テーブル ${t.physicalName} の列が0の制約を削除');
            return true;
          }
          return false;
        });
      }
      for (final k in t.checks) {
        final before = k.conditions.length;
        k.conditions.removeWhere((x) => !valid(x.columnId));
        if (k.conditions.length != before) {
          rep.add('テーブル ${t.physicalName} のCHECK制約の存在しない列の条件を削除');
        }
      }
      for (final g in t.triggers) {
        final before = g.updateColumnIds.length;
        g.updateColumnIds.removeWhere((id) => !valid(id));
        if (g.updateColumnIds.length != before) {
          rep.add('テーブル ${t.physicalName} のトリガーの存在しないUPDATE列を削除');
        }
      }
      t.triggers.removeWhere((g) {
        if (g.source == TriggerSource.public &&
            (g.methodId == null || !methodIds.contains(g.methodId))) {
          rep.add('テーブル ${t.physicalName} のトリガーのメソッドが存在しないため削除');
          return true;
        }
        if (g.events.isEmpty) {
          g.events = [TriggerEvent.insert];
          rep.add('テーブル ${t.physicalName} のトリガーのイベントを補完');
        }
        return false;
      });
    }

    for (final v in m.views) {
      v.sql.columns.removeWhere((c) {
        if (!typeIds.contains(c.typeId)) {
          rep.add('ビュー ${v.physicalName} の列の型が存在しないため削除');
          return true;
        }
        return false;
      });
      final f = v.function;
      if (f.methodId != null && !methodIds.contains(f.methodId)) {
        rep.add('ビュー ${v.physicalName} のメソッドが存在しないため解除');
        f.methodId = null;
      }
      f.columns.removeWhere((c) {
        if (!typeIds.contains(c.typeId)) {
          rep.add('ビュー ${v.physicalName} の戻り列の型が存在しないため削除');
          return true;
        }
        return false;
      });
      final j = v.join;
      j.sources.removeWhere((s) {
        if (!tableIds.contains(s.entityId)) {
          rep.add('ビュー ${v.physicalName} のソースが存在しないため削除');
          return true;
        }
        return false;
      });
      final aliases = j.sources.map((s) => s.alias).toSet();
      for (final s in j.sources) {
        s.on.removeWhere((o) {
          final bad = !aliases.contains(o.leftAlias) ||
              m.anyColumnById(o.leftColumnId) == null ||
              m.anyColumnById(o.rightColumnId) == null;
          if (bad) rep.add('ビュー ${v.physicalName} の不正な結合条件を削除');
          return bad;
        });
      }
      j.columns.removeWhere((c) {
        final bad = !aliases.contains(c.alias) || m.anyColumnById(c.columnId) == null;
        if (bad) rep.add('ビュー ${v.physicalName} の不正な出力列を削除');
        return bad;
      });
    }
  }

  static void _repairRelationships(ErModel m, Repairs rep) {
    m.relationships.removeWhere((r) {
      final p = m.tableById(r.parentId);
      final c = m.tableById(r.childId);
      if (p == null || c == null) {
        rep.add('リレーションシップ ${r.id} の端点が存在しないため削除');
        return true;
      }
      for (final pair in r.columnPairs) {
        final okP = p.columnById(pair.parentColumnId) != null ||
            m.patternColumnById(pair.parentColumnId) != null;
        final okC = c.columnById(pair.childColumnId) != null ||
            m.patternColumnById(pair.childColumnId) != null;
        if (!okP || !okC) {
          rep.add('リレーションシップ ${r.id} の列対応が存在しないため削除');
          return true;
        }
      }
      return false;
    });
  }

  static void _repairDiagrams(ErModel m, Repairs rep) {
    if (m.diagrams.isEmpty) {
      m.diagrams.add(Diagram(id: m.allocateId(), name: 'ダイアグラム1'));
      rep.add('ダイアグラムが無いため追加');
    }
    for (final d in m.diagrams) {
      final seen = <int>{};
      d.placements.removeWhere((p) {
        if (m.entityById(p.entityId) == null || !seen.add(p.entityId)) {
          rep.add('ダイアグラム ${d.name} の不正な配置を削除');
          return true;
        }
        return false;
      });
    }
  }
}
