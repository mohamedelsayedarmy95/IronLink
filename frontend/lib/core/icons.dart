import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Icon vocabulary for the app, named for what things *mean* rather than for
/// the glyph or the vendor. Call sites say `IronIcons.send`, so swapping the
/// underlying set later touches this file alone, and a reviewer can see at a
/// glance that "attach" and "paperclip" are the same decision.
///
/// The set is Lucide, per the spec: consistent 2px-grid strokes and outline
/// forms. Material's mixed outlined/filled/rounded families were the reason
/// the old interface looked assembled from several products.
///
/// **Directional icons** use Lucide's `…Dir` variants, which carry
/// `matchTextDirection: true` and mirror automatically under RTL. Arrows and
/// chevrons are the only icons that should ever be direction-dependent —
/// mirroring a lock or a microphone is just a backwards lock.
class IronIcons {
  const IronIcons._();

  // ── Sizing ──────────────────────────────────────────────────────────────
  /// Markers riding alongside small text: delivery ticks, role badges,
  /// metadata rows. Call sites had drifted to 13/14/15/16 for the same job.
  static const double sizeCompact = 16;

  /// Inline with text: list leading marks, field affixes, inline status.
  static const double sizeInline = 20;

  /// Navigation and primary actions — bottom bar, app bar, send.
  static const double sizeNav = 24;

  /// Empty and error states, where the icon is the largest element.
  static const double sizeDisplay = 32;

  /// Mark inside an empty state.
  static const double sizeEmptyState = 32;

  // ── Navigation ──────────────────────────────────────────────────────────
  /// Mirrors under RTL, so "back" always points away from the reading start.
  static const IconData back = LucideIcons.arrowLeftDir;

  /// Disclosure on a tappable row. Points toward the reading direction:
  /// right in English, left in Arabic, without a per-locale branch.
  static const IconData forward = LucideIcons.chevronRightDir;

  static const IconData close = LucideIcons.x;
  static const IconData add = LucideIcons.plus;
  static const IconData refresh = LucideIcons.refreshCw;

  // ── Tabs ────────────────────────────────────────────────────────────────
  static const IconData chats = LucideIcons.messageCircle;
  static const IconData groups = LucideIcons.users;
  static const IconData contacts = LucideIcons.contact;
  static const IconData broadcasts = LucideIcons.megaphone;
  static const IconData settings = LucideIcons.settings;

  // ── Security & identity ─────────────────────────────────────────────────
  static const IconData shield = LucideIcons.shield;
  static const IconData shieldAlert = LucideIcons.shieldAlert;
  static const IconData lock = LucideIcons.lock;

  /// An open padlock, not a crossed-out one: this marks an ordinary chat,
  /// which is a normal state rather than an error.
  static const IconData unlock = LucideIcons.lockOpen;
  static const IconData verified = LucideIcons.badgeCheck;
  static const IconData militaryId = LucideIcons.idCard;
  static const IconData admin = LucideIcons.star;
  static const IconData observer = LucideIcons.eye;
  static const IconData device = LucideIcons.smartphone;
  static const IconData privacy = LucideIcons.eyeClosed;

  // ── Messaging ───────────────────────────────────────────────────────────
  static const IconData send = LucideIcons.send;
  static const IconData attach = LucideIcons.paperclip;
  static const IconData mic = LucideIcons.mic;
  static const IconData translate = LucideIcons.languages;
  static const IconData summary = LucideIcons.fileText;
  static const IconData report = LucideIcons.shieldAlert;
  static const IconData blocked = LucideIcons.ban;
  static const IconData online = LucideIcons.zap;
  static const IconData channel = LucideIcons.megaphone;
  static const IconData subscribers = LucideIcons.users;

  // ── Delivery receipts ───────────────────────────────────────────────────
  static const IconData pending = LucideIcons.clock;
  static const IconData sent = LucideIcons.check;
  static const IconData delivered = LucideIcons.checkCheck;

  // ── Media ───────────────────────────────────────────────────────────────
  static const IconData play = LucideIcons.circlePlay;
  static const IconData pause = LucideIcons.circlePause;
  static const IconData camera = LucideIcons.camera;
  static const IconData gallery = LucideIcons.images;
  static const IconData document = LucideIcons.fileText;
  static const IconData speed = LucideIcons.gauge;
  static const IconData tapHint = LucideIcons.pointer;

  // ── Status & feedback ───────────────────────────────────────────────────
  static const IconData success = LucideIcons.circleCheck;
  static const IconData error = LucideIcons.circleAlert;
  static const IconData info = LucideIcons.info;
  static const IconData offline = LucideIcons.cloudOff;
  static const IconData noSignal = LucideIcons.wifiOff;
  static const IconData delete = LucideIcons.trash2;

  /// Overflow menu. Vertical dots rather than horizontal: the vertical form
  /// does not need mirroring in a right-to-left layout.
  static const IconData more = LucideIcons.ellipsisVertical;

  // ── Selection ───────────────────────────────────────────────────────────
  // Drawn rather than using a Radio widget so the choice reads the same in
  // both directions of a bidirectional layout.
  static const IconData radioOn = LucideIcons.circleDot;
  static const IconData radioOff = LucideIcons.circle;

  // ── Settings ────────────────────────────────────────────────────────────
  static const IconData keyword = LucideIcons.tag;
  static const IconData search = LucideIcons.search;
  static const IconData keywordSearch = LucideIcons.fileSearch;
  static const IconData show = LucideIcons.eye;
  static const IconData hide = LucideIcons.eyeOff;
}
