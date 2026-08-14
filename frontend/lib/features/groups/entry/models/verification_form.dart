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
