import 'dart:math' as math;
import 'dart:ui';

import '../model/model.dart';

/// リレーションシップの描画上の線分(モデル座標)。
class RelationshipSegment {
  RelationshipSegment({
    required this.relationship,
    required this.from,
    required this.to,
    required this.bothPlaced,
    this.fromIsParent = true,
    this.label,
  });
  final Relationship relationship;

  /// 親側の端点。片端のみ配置のときは、配置されている側の端点。
  final Offset from;

  /// 子側の端点(片端のみのときは線の先端)。
  final Offset to;
  final bool bothPlaced;

  /// [from] が親側の端点か。
  final bool fromIsParent;

  /// 片端のみ配置のときの、相手エンティティの表示名(5.2-6)。
  final String? label;

  Offset get mid => Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);

  /// 点から線分までの距離。
  double distanceTo(Offset p) {
    final d = to - from;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    if (len2 == 0) return (p - from).distance;
    final t = (((p.dx - from.dx) * d.dx + (p.dy - from.dy) * d.dy) / len2).clamp(0.0, 1.0);
    return (p - Offset(from.dx + d.dx * t, from.dy + d.dy * t)).distance;
  }
}

/// 矩形と、矩形の中心から外へ向かう直線との交点(境界で切る)。
Offset clipToRect(Rect r, Offset toward) {
  final c = r.center;
  final d = toward - c;
  if (d == Offset.zero) return c;
  final sx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
  final sy = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
  final s = math.min(sx, sy);
  return Offset(c.dx + d.dx * s, c.dy + d.dy * s);
}

/// 現在のダイアグラムに表示するリレーションシップの線分を求める(5.2-6、7-2)。
/// [rectOf] は、配置されているエンティティの矩形(ドラッグ中の位置を反映したもの)を返す。
List<RelationshipSegment> relationshipSegments(
  ErModel model,
  Diagram diagram,
  Rect? Function(int entityId) rectOf,
  double headerHeight,
) {
  final out = <RelationshipSegment>[];
  // 片端のみ配置: 同じ側(エンティティごと)に複数ある場合は縦に16pxずつずらす。
  final stub = <int, int>{};
  for (final r in model.relationships) {
    final pr = rectOf(r.parentId);
    final cr = rectOf(r.childId);
    if (pr != null && cr != null) {
      out.add(RelationshipSegment(
        relationship: r,
        from: clipToRect(pr, cr.center),
        to: clipToRect(cr, pr.center),
        bothPlaced: true,
      ));
    } else if (pr != null || cr != null) {
      final placedId = pr != null ? r.parentId : r.childId;
      final rect = (pr ?? cr)!;
      final otherId = pr != null ? r.childId : r.parentId;
      final k = stub[placedId] = (stub[placedId] ?? -1) + 1;
      final y = rect.top + headerHeight / 2 + k * 16;
      out.add(RelationshipSegment(
        relationship: r,
        from: Offset(rect.right, y),
        to: Offset(rect.right + 40, y),
        bothPlaced: false,
        fromIsParent: pr != null,
        label: model.entityById(otherId)?.displayLabel ?? '',
      ));
    }
  }
  return out;
}
