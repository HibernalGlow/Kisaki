// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'types.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FieldPayload {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as FieldPayload;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldPayload&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as FieldPayload;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as FieldPayload;
  return 'FieldPayload(field0: ${_this.field0})';
}


}

/// @nodoc
class $FieldPayloadCopyWith<$Res>  {
$FieldPayloadCopyWith(FieldPayload _, $Res Function(FieldPayload) __);
}


/// Adds pattern-matching-related methods to [FieldPayload].
extension FieldPayloadPatterns on FieldPayload {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FieldPayload_Flag value)?  flag,TResult Function( FieldPayload_Choice value)?  choice,TResult Function( FieldPayload_Integer value)?  integer,TResult Function( FieldPayload_Text value)?  text,TResult Function( FieldPayload_Tokens value)?  tokens,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FieldPayload_Flag() when flag != null:
return flag(_that);case FieldPayload_Choice() when choice != null:
return choice(_that);case FieldPayload_Integer() when integer != null:
return integer(_that);case FieldPayload_Text() when text != null:
return text(_that);case FieldPayload_Tokens() when tokens != null:
return tokens(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FieldPayload_Flag value)  flag,required TResult Function( FieldPayload_Choice value)  choice,required TResult Function( FieldPayload_Integer value)  integer,required TResult Function( FieldPayload_Text value)  text,required TResult Function( FieldPayload_Tokens value)  tokens,}){
final _that = this;
switch (_that) {
case FieldPayload_Flag():
return flag(_that);case FieldPayload_Choice():
return choice(_that);case FieldPayload_Integer():
return integer(_that);case FieldPayload_Text():
return text(_that);case FieldPayload_Tokens():
return tokens(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FieldPayload_Flag value)?  flag,TResult? Function( FieldPayload_Choice value)?  choice,TResult? Function( FieldPayload_Integer value)?  integer,TResult? Function( FieldPayload_Text value)?  text,TResult? Function( FieldPayload_Tokens value)?  tokens,}){
final _that = this;
switch (_that) {
case FieldPayload_Flag() when flag != null:
return flag(_that);case FieldPayload_Choice() when choice != null:
return choice(_that);case FieldPayload_Integer() when integer != null:
return integer(_that);case FieldPayload_Text() when text != null:
return text(_that);case FieldPayload_Tokens() when tokens != null:
return tokens(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool field0)?  flag,TResult Function( String field0)?  choice,TResult Function( PlatformInt64 field0)?  integer,TResult Function( String field0)?  text,TResult Function( List<String> field0)?  tokens,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FieldPayload_Flag() when flag != null:
return flag(_that.field0);case FieldPayload_Choice() when choice != null:
return choice(_that.field0);case FieldPayload_Integer() when integer != null:
return integer(_that.field0);case FieldPayload_Text() when text != null:
return text(_that.field0);case FieldPayload_Tokens() when tokens != null:
return tokens(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool field0)  flag,required TResult Function( String field0)  choice,required TResult Function( PlatformInt64 field0)  integer,required TResult Function( String field0)  text,required TResult Function( List<String> field0)  tokens,}) {final _that = this;
switch (_that) {
case FieldPayload_Flag():
return flag(_that.field0);case FieldPayload_Choice():
return choice(_that.field0);case FieldPayload_Integer():
return integer(_that.field0);case FieldPayload_Text():
return text(_that.field0);case FieldPayload_Tokens():
return tokens(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool field0)?  flag,TResult? Function( String field0)?  choice,TResult? Function( PlatformInt64 field0)?  integer,TResult? Function( String field0)?  text,TResult? Function( List<String> field0)?  tokens,}) {final _that = this;
switch (_that) {
case FieldPayload_Flag() when flag != null:
return flag(_that.field0);case FieldPayload_Choice() when choice != null:
return choice(_that.field0);case FieldPayload_Integer() when integer != null:
return integer(_that.field0);case FieldPayload_Text() when text != null:
return text(_that.field0);case FieldPayload_Tokens() when tokens != null:
return tokens(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class FieldPayload_Flag extends FieldPayload {
  const FieldPayload_Flag(this.field0): super._();
  

@override final  bool field0;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldPayload_FlagCopyWith<FieldPayload_Flag> get copyWith => _$FieldPayload_FlagCopyWithImpl<FieldPayload_Flag>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldPayload_Flag&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'FieldPayload.flag(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FieldPayload_FlagCopyWith<$Res> implements $FieldPayloadCopyWith<$Res> {
  factory $FieldPayload_FlagCopyWith(FieldPayload_Flag value, $Res Function(FieldPayload_Flag) _then) = _$FieldPayload_FlagCopyWithImpl;
@useResult
$Res call({
 bool field0
});




}
/// @nodoc
class _$FieldPayload_FlagCopyWithImpl<$Res>
    implements $FieldPayload_FlagCopyWith<$Res> {
  _$FieldPayload_FlagCopyWithImpl(this._self, this._then);

  final FieldPayload_Flag _self;
  final $Res Function(FieldPayload_Flag) _then;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FieldPayload_Flag(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FieldPayload_Choice extends FieldPayload {
  const FieldPayload_Choice(this.field0): super._();
  

@override final  String field0;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldPayload_ChoiceCopyWith<FieldPayload_Choice> get copyWith => _$FieldPayload_ChoiceCopyWithImpl<FieldPayload_Choice>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldPayload_Choice&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'FieldPayload.choice(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FieldPayload_ChoiceCopyWith<$Res> implements $FieldPayloadCopyWith<$Res> {
  factory $FieldPayload_ChoiceCopyWith(FieldPayload_Choice value, $Res Function(FieldPayload_Choice) _then) = _$FieldPayload_ChoiceCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$FieldPayload_ChoiceCopyWithImpl<$Res>
    implements $FieldPayload_ChoiceCopyWith<$Res> {
  _$FieldPayload_ChoiceCopyWithImpl(this._self, this._then);

  final FieldPayload_Choice _self;
  final $Res Function(FieldPayload_Choice) _then;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FieldPayload_Choice(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FieldPayload_Integer extends FieldPayload {
  const FieldPayload_Integer(this.field0): super._();
  

@override final  PlatformInt64 field0;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldPayload_IntegerCopyWith<FieldPayload_Integer> get copyWith => _$FieldPayload_IntegerCopyWithImpl<FieldPayload_Integer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldPayload_Integer&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'FieldPayload.integer(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FieldPayload_IntegerCopyWith<$Res> implements $FieldPayloadCopyWith<$Res> {
  factory $FieldPayload_IntegerCopyWith(FieldPayload_Integer value, $Res Function(FieldPayload_Integer) _then) = _$FieldPayload_IntegerCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 field0
});




}
/// @nodoc
class _$FieldPayload_IntegerCopyWithImpl<$Res>
    implements $FieldPayload_IntegerCopyWith<$Res> {
  _$FieldPayload_IntegerCopyWithImpl(this._self, this._then);

  final FieldPayload_Integer _self;
  final $Res Function(FieldPayload_Integer) _then;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FieldPayload_Integer(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class FieldPayload_Text extends FieldPayload {
  const FieldPayload_Text(this.field0): super._();
  

@override final  String field0;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldPayload_TextCopyWith<FieldPayload_Text> get copyWith => _$FieldPayload_TextCopyWithImpl<FieldPayload_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldPayload_Text&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'FieldPayload.text(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FieldPayload_TextCopyWith<$Res> implements $FieldPayloadCopyWith<$Res> {
  factory $FieldPayload_TextCopyWith(FieldPayload_Text value, $Res Function(FieldPayload_Text) _then) = _$FieldPayload_TextCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$FieldPayload_TextCopyWithImpl<$Res>
    implements $FieldPayload_TextCopyWith<$Res> {
  _$FieldPayload_TextCopyWithImpl(this._self, this._then);

  final FieldPayload_Text _self;
  final $Res Function(FieldPayload_Text) _then;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FieldPayload_Text(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FieldPayload_Tokens extends FieldPayload {
  const FieldPayload_Tokens( List<String> field0): _field0 = field0,super._();
  

 final  List<String> _field0;
@override List<String> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldPayload_TokensCopyWith<FieldPayload_Tokens> get copyWith => _$FieldPayload_TokensCopyWithImpl<FieldPayload_Tokens>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldPayload_Tokens&&const DeepCollectionEquality().equals(other.field0, _field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));
}

@override
String toString() {
    return 'FieldPayload.tokens(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $FieldPayload_TokensCopyWith<$Res> implements $FieldPayloadCopyWith<$Res> {
  factory $FieldPayload_TokensCopyWith(FieldPayload_Tokens value, $Res Function(FieldPayload_Tokens) _then) = _$FieldPayload_TokensCopyWithImpl;
@useResult
$Res call({
 List<String> field0
});




}
/// @nodoc
class _$FieldPayload_TokensCopyWithImpl<$Res>
    implements $FieldPayload_TokensCopyWith<$Res> {
  _$FieldPayload_TokensCopyWithImpl(this._self, this._then);

  final FieldPayload_Tokens _self;
  final $Res Function(FieldPayload_Tokens) _then;

/// Create a copy of FieldPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(FieldPayload_Tokens(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
mixin _$ScanEvent {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as ScanEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as ScanEvent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as ScanEvent;
  return 'ScanEvent(field0: ${_this.field0})';
}


}

/// @nodoc
class $ScanEventCopyWith<$Res>  {
$ScanEventCopyWith(ScanEvent _, $Res Function(ScanEvent) __);
}


/// Adds pattern-matching-related methods to [ScanEvent].
extension ScanEventPatterns on ScanEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ScanEvent_Progress value)?  progress,TResult Function( ScanEvent_Completed value)?  completed,TResult Function( ScanEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ScanEvent_Progress() when progress != null:
return progress(_that);case ScanEvent_Completed() when completed != null:
return completed(_that);case ScanEvent_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ScanEvent_Progress value)  progress,required TResult Function( ScanEvent_Completed value)  completed,required TResult Function( ScanEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case ScanEvent_Progress():
return progress(_that);case ScanEvent_Completed():
return completed(_that);case ScanEvent_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ScanEvent_Progress value)?  progress,TResult? Function( ScanEvent_Completed value)?  completed,TResult? Function( ScanEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case ScanEvent_Progress() when progress != null:
return progress(_that);case ScanEvent_Completed() when completed != null:
return completed(_that);case ScanEvent_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProgressUpdate field0)?  progress,TResult Function( ScanOutcome field0)?  completed,TResult Function( String field0)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ScanEvent_Progress() when progress != null:
return progress(_that.field0);case ScanEvent_Completed() when completed != null:
return completed(_that.field0);case ScanEvent_Failed() when failed != null:
return failed(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProgressUpdate field0)  progress,required TResult Function( ScanOutcome field0)  completed,required TResult Function( String field0)  failed,}) {final _that = this;
switch (_that) {
case ScanEvent_Progress():
return progress(_that.field0);case ScanEvent_Completed():
return completed(_that.field0);case ScanEvent_Failed():
return failed(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProgressUpdate field0)?  progress,TResult? Function( ScanOutcome field0)?  completed,TResult? Function( String field0)?  failed,}) {final _that = this;
switch (_that) {
case ScanEvent_Progress() when progress != null:
return progress(_that.field0);case ScanEvent_Completed() when completed != null:
return completed(_that.field0);case ScanEvent_Failed() when failed != null:
return failed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ScanEvent_Progress extends ScanEvent {
  const ScanEvent_Progress(this.field0): super._();
  

@override final  ProgressUpdate field0;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanEvent_ProgressCopyWith<ScanEvent_Progress> get copyWith => _$ScanEvent_ProgressCopyWithImpl<ScanEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent_Progress&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanEvent.progress(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanEvent_ProgressCopyWith<$Res> implements $ScanEventCopyWith<$Res> {
  factory $ScanEvent_ProgressCopyWith(ScanEvent_Progress value, $Res Function(ScanEvent_Progress) _then) = _$ScanEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 ProgressUpdate field0
});




}
/// @nodoc
class _$ScanEvent_ProgressCopyWithImpl<$Res>
    implements $ScanEvent_ProgressCopyWith<$Res> {
  _$ScanEvent_ProgressCopyWithImpl(this._self, this._then);

  final ScanEvent_Progress _self;
  final $Res Function(ScanEvent_Progress) _then;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanEvent_Progress(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ProgressUpdate,
  ));
}


}

/// @nodoc


class ScanEvent_Completed extends ScanEvent {
  const ScanEvent_Completed(this.field0): super._();
  

@override final  ScanOutcome field0;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanEvent_CompletedCopyWith<ScanEvent_Completed> get copyWith => _$ScanEvent_CompletedCopyWithImpl<ScanEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent_Completed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanEvent.completed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanEvent_CompletedCopyWith<$Res> implements $ScanEventCopyWith<$Res> {
  factory $ScanEvent_CompletedCopyWith(ScanEvent_Completed value, $Res Function(ScanEvent_Completed) _then) = _$ScanEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 ScanOutcome field0
});




}
/// @nodoc
class _$ScanEvent_CompletedCopyWithImpl<$Res>
    implements $ScanEvent_CompletedCopyWith<$Res> {
  _$ScanEvent_CompletedCopyWithImpl(this._self, this._then);

  final ScanEvent_Completed _self;
  final $Res Function(ScanEvent_Completed) _then;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanEvent_Completed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as ScanOutcome,
  ));
}


}

/// @nodoc


class ScanEvent_Failed extends ScanEvent {
  const ScanEvent_Failed(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScanEvent_FailedCopyWith<ScanEvent_Failed> get copyWith => _$ScanEvent_FailedCopyWithImpl<ScanEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ScanEvent_Failed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ScanEvent.failed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ScanEvent_FailedCopyWith<$Res> implements $ScanEventCopyWith<$Res> {
  factory $ScanEvent_FailedCopyWith(ScanEvent_Failed value, $Res Function(ScanEvent_Failed) _then) = _$ScanEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ScanEvent_FailedCopyWithImpl<$Res>
    implements $ScanEvent_FailedCopyWith<$Res> {
  _$ScanEvent_FailedCopyWithImpl(this._self, this._then);

  final ScanEvent_Failed _self;
  final $Res Function(ScanEvent_Failed) _then;

/// Create a copy of ScanEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ScanEvent_Failed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
