import 'package:equatable/equatable.dart';

/// Field types an admin can place on a verification form.
///
/// The wire values match the backend's FormFieldType verbatim. An unknown
/// value maps to [unsupported] rather than throwing: a server that adds a
/// field type should not crash an older client mid-form.
enum FormFieldType {
  textShort('text_short'),
  textLong('text_long'),
  number('number'),
  selectSingle('select_single'),
  selectMulti('select_multi'),
  date('date'),
  phone('phone'),
  file('file'),
  image('image'),
  checkbox('checkbox'),
  url('url'),
  email('email'),
  unsupported('__unsupported__');

  const FormFieldType(this.wire);
  final String wire;

  static FormFieldType fromWire(String value) => FormFieldType.values.firstWhere(
        (t) => t.wire == value,
        orElse: () => FormFieldType.unsupported,
      );

  /// Whether an answer for this type is a list rather than a scalar.
  bool get isMultiValue => this == FormFieldType.selectMulti;
}

class FormFieldOption extends Equatable {
  const FormFieldOption({required this.label, required this.value});

  final String label;
  final String value;

  factory FormFieldOption.fromJson(Map<String, dynamic> json) => FormFieldOption(
        label: json['label']?.toString() ?? '',
        value: json['value']?.toString() ?? '',
      );

  @override
  List<Object?> get props => [label, value];
}

class VerificationFormField extends Equatable {
  const VerificationFormField({
    required this.id,
    required this.type,
    required this.label,
    required this.isRequired,
    this.placeholder,
    this.helperText,
    this.validationRules = const {},
    this.options = const [],
    this.orderIndex = 0,
  });

  final String id;
  final FormFieldType type;
  final String label;
  final bool isRequired;
  final String? placeholder;
  final String? helperText;
  final Map<String, dynamic> validationRules;
  final List<FormFieldOption> options;
  final int orderIndex;

  int? get minLength => validationRules['min'] as int?;
  int? get maxLength => validationRules['max'] as int?;
  int? get minSelect => validationRules['min_select'] as int?;
  int? get maxSelect => validationRules['max_select'] as int?;

  factory VerificationFormField.fromJson(Map<String, dynamic> json) {
    final rawOptions =
        (json['options'] as Map<String, dynamic>?)?['options'] as List<dynamic>?;
    return VerificationFormField(
      id: json['id'] as String,
      type: FormFieldType.fromWire(json['field_type'] as String? ?? ''),
      label: json['label'] as String? ?? '',
      isRequired: json['is_required'] as bool? ?? true,
      placeholder: json['placeholder'] as String?,
      helperText: json['helper_text'] as String?,
      validationRules:
          (json['validation_rules'] as Map<String, dynamic>?) ?? const {},
      options: rawOptions
              ?.whereType<Map<String, dynamic>>()
              .map(FormFieldOption.fromJson)
              .toList() ??
          const [],
      orderIndex: json['order_index'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, type, label, isRequired, orderIndex];
}

class VerificationForm extends Equatable {
  const VerificationForm({
    required this.id,
    required this.name,
    required this.fields,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final List<VerificationFormField> fields;

  /// Only required fields count toward progress — showing "2 of 7" when five
  /// of those are optional misrepresents how much is actually left to do.
  int get requiredFieldCount => fields.where((f) => f.isRequired).length;

  factory VerificationForm.fromJson(Map<String, dynamic> json) {
    final fields = (json['fields'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(VerificationFormField.fromJson)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return VerificationForm(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      fields: fields,
    );
  }

  @override
  List<Object?> get props => [id, name, fields];
}

/// How a group admits people.
enum GroupJoinMode {
  open('open'),
  inviteOnly('invite_only'),
  requestApproval('request_approval');

  const GroupJoinMode(this.wire);
  final String wire;

  static GroupJoinMode fromWire(String value) => GroupJoinMode.values.firstWhere(
        (m) => m.wire == value,
        // Approval-required is the safe fallback: an unrecognised mode must
        // not silently open a group that was meant to be gated.
        orElse: () => GroupJoinMode.requestApproval,
      );

  /// Whether a verification form is meaningful for this mode. Open and
  /// invite-only groups never show the form, so attaching one would be a
  /// setting with no effect.
  bool get usesForm => this == GroupJoinMode.requestApproval;
}

/// Entry configuration for a group, as the admin sees and edits it.
class GroupEntrySettings extends Equatable {
  const GroupEntrySettings({
    required this.joinMode,
    this.verificationFormId,
    this.requestExpiryDays = 14,
    this.allowRejoin = false,
  });

  final GroupJoinMode joinMode;
  final String? verificationFormId;

  /// 0 means requests never expire.
  final int requestExpiryDays;
  final bool allowRejoin;

  GroupEntrySettings copyWith({
    GroupJoinMode? joinMode,
    String? verificationFormId,
    bool clearForm = false,
    int? requestExpiryDays,
    bool? allowRejoin,
  }) =>
      GroupEntrySettings(
        joinMode: joinMode ?? this.joinMode,
        verificationFormId:
            clearForm ? null : (verificationFormId ?? this.verificationFormId),
        requestExpiryDays: requestExpiryDays ?? this.requestExpiryDays,
        allowRejoin: allowRejoin ?? this.allowRejoin,
      );

  Map<String, dynamic> toJson() => {
        'join_mode': joinMode.wire,
        'verification_form_id': verificationFormId,
        'request_expiry_days': requestExpiryDays,
        'allow_rejoin': allowRejoin,
      };

  @override
  List<Object?> get props =>
      [joinMode, verificationFormId, requestExpiryDays, allowRejoin];
}

/// Where a join request stands. Wire values match the backend.
enum JoinRequestStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected'),
  moreInfoNeeded('more_info_needed'),
  expired('expired');

  const JoinRequestStatus(this.wire);
  final String wire;

  static JoinRequestStatus fromWire(String value) =>
      JoinRequestStatus.values.firstWhere(
        (s) => s.wire == value,
        orElse: () => JoinRequestStatus.pending,
      );

  /// Whether the requester may still change their answers.
  bool get isEditable => this == JoinRequestStatus.moreInfoNeeded;

  /// Whether a fresh request is the way forward from here.
  bool get allowsNewRequest => this == JoinRequestStatus.expired;
}

/// A recorded sensitive action. Wire values match GroupAuditAction.
enum AuditAction {
  approveRequest('approve_request'),
  rejectRequest('reject_request'),
  requestMoreInfo('request_more_info'),
  bulkApprove('bulk_approve'),
  bulkReject('bulk_reject'),
  removeMember('remove_member'),
  banMember('ban_member'),
  unbanMember('unban_member'),
  changeJoinMode('change_join_mode'),
  updateForm('update_form'),
  assignModerator('assign_moderator'),
  reopenRequest('reopen_request'),
  exportAuditLog('export_audit_log'),
  unknown('__unknown__');

  const AuditAction(this.wire);
  final String wire;

  static AuditAction fromWire(String value) => AuditAction.values.firstWhere(
        (a) => a.wire == value,
        // An action this build doesn't know still appears in the log with its
        // raw name — dropping it would leave a gap in an audit trail.
        orElse: () => AuditAction.unknown,
      );
}

class AuditEntry extends Equatable {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.rawAction,
    required this.performedById,
    this.targetUserId,
    this.details = const {},
    this.createdAt,
  });

  final String id;
  final AuditAction action;

  /// Kept so an unrecognised action can still be displayed by name.
  final String rawAction;
  final String performedById;
  final String? targetUserId;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  /// Free-text detail worth showing on its own line: a rejection reason, the
  /// notes attached to a more-info request, or a bulk count.
  String? get detailLine {
    final reason = details['reason'];
    if (reason is String && reason.trim().isNotEmpty) return reason;
    final notes = details['notes'];
    if (notes is String && notes.trim().isNotEmpty) return notes;
    return null;
  }

  int? get count => (details['count'] as num?)?.toInt();

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['action'] as String? ?? '';
    return AuditEntry(
      id: json['id'] as String,
      action: AuditAction.fromWire(raw),
      rawAction: raw,
      performedById: json['performed_by_id'] as String? ?? '',
      targetUserId: json['target_user_id'] as String?,
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, action, createdAt];
}

class JoinRequest extends Equatable {
  const JoinRequest({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.status,
    this.answers = const {},
    this.message,
    this.adminNotes,
    this.rejectionReason,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String groupId;
  final String userId;
  final JoinRequestStatus status;
  final Map<String, dynamic> answers;
  final String? message;

  /// What the admin said they still need. Shown verbatim to the requester,
  /// so it is the admin's words rather than a generated summary.
  final String? adminNotes;
  final String? rejectionReason;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory JoinRequest.fromJson(Map<String, dynamic> json) => JoinRequest(
        id: json['id'] as String,
        groupId: json['group_id'] as String,
        userId: json['user_id'] as String,
        status: JoinRequestStatus.fromWire(json['status'] as String? ?? ''),
        answers: (json['answers'] as Map<String, dynamic>?) ?? const {},
        message: json['message'] as String?,
        adminNotes: json['admin_notes'] as String?,
        rejectionReason: json['rejection_reason'] as String?,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.tryParse(json['expires_at'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'] as String),
      );

  @override
  List<Object?> get props => [id, status, answers, adminNotes];
}
