// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reader.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReaderError {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as ReaderError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as ReaderError;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as ReaderError;
  return 'ReaderError(field0: ${_this.field0})';
}


}

/// @nodoc
class $ReaderErrorCopyWith<$Res>  {
$ReaderErrorCopyWith(ReaderError _, $Res Function(ReaderError) __);
}


/// Adds pattern-matching-related methods to [ReaderError].
extension ReaderErrorPatterns on ReaderError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ReaderError_InvalidPath value)?  invalidPath,TResult Function( ReaderError_UnsupportedFormat value)?  unsupportedFormat,TResult Function( ReaderError_OpenFailed value)?  openFailed,TResult Function( ReaderError_UnknownSession value)?  unknownSession,TResult Function( ReaderError_InvalidSection value)?  invalidSection,TResult Function( ReaderError_ContentFailed value)?  contentFailed,TResult Function( ReaderError_SearchFailed value)?  searchFailed,TResult Function( ReaderError_LocatorFailed value)?  locatorFailed,TResult Function( ReaderError_PaginationFailed value)?  paginationFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ReaderError_InvalidPath() when invalidPath != null:
return invalidPath(_that);case ReaderError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that);case ReaderError_OpenFailed() when openFailed != null:
return openFailed(_that);case ReaderError_UnknownSession() when unknownSession != null:
return unknownSession(_that);case ReaderError_InvalidSection() when invalidSection != null:
return invalidSection(_that);case ReaderError_ContentFailed() when contentFailed != null:
return contentFailed(_that);case ReaderError_SearchFailed() when searchFailed != null:
return searchFailed(_that);case ReaderError_LocatorFailed() when locatorFailed != null:
return locatorFailed(_that);case ReaderError_PaginationFailed() when paginationFailed != null:
return paginationFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ReaderError_InvalidPath value)  invalidPath,required TResult Function( ReaderError_UnsupportedFormat value)  unsupportedFormat,required TResult Function( ReaderError_OpenFailed value)  openFailed,required TResult Function( ReaderError_UnknownSession value)  unknownSession,required TResult Function( ReaderError_InvalidSection value)  invalidSection,required TResult Function( ReaderError_ContentFailed value)  contentFailed,required TResult Function( ReaderError_SearchFailed value)  searchFailed,required TResult Function( ReaderError_LocatorFailed value)  locatorFailed,required TResult Function( ReaderError_PaginationFailed value)  paginationFailed,}){
final _that = this;
switch (_that) {
case ReaderError_InvalidPath():
return invalidPath(_that);case ReaderError_UnsupportedFormat():
return unsupportedFormat(_that);case ReaderError_OpenFailed():
return openFailed(_that);case ReaderError_UnknownSession():
return unknownSession(_that);case ReaderError_InvalidSection():
return invalidSection(_that);case ReaderError_ContentFailed():
return contentFailed(_that);case ReaderError_SearchFailed():
return searchFailed(_that);case ReaderError_LocatorFailed():
return locatorFailed(_that);case ReaderError_PaginationFailed():
return paginationFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ReaderError_InvalidPath value)?  invalidPath,TResult? Function( ReaderError_UnsupportedFormat value)?  unsupportedFormat,TResult? Function( ReaderError_OpenFailed value)?  openFailed,TResult? Function( ReaderError_UnknownSession value)?  unknownSession,TResult? Function( ReaderError_InvalidSection value)?  invalidSection,TResult? Function( ReaderError_ContentFailed value)?  contentFailed,TResult? Function( ReaderError_SearchFailed value)?  searchFailed,TResult? Function( ReaderError_LocatorFailed value)?  locatorFailed,TResult? Function( ReaderError_PaginationFailed value)?  paginationFailed,}){
final _that = this;
switch (_that) {
case ReaderError_InvalidPath() when invalidPath != null:
return invalidPath(_that);case ReaderError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that);case ReaderError_OpenFailed() when openFailed != null:
return openFailed(_that);case ReaderError_UnknownSession() when unknownSession != null:
return unknownSession(_that);case ReaderError_InvalidSection() when invalidSection != null:
return invalidSection(_that);case ReaderError_ContentFailed() when contentFailed != null:
return contentFailed(_that);case ReaderError_SearchFailed() when searchFailed != null:
return searchFailed(_that);case ReaderError_LocatorFailed() when locatorFailed != null:
return locatorFailed(_that);case ReaderError_PaginationFailed() when paginationFailed != null:
return paginationFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String field0)?  invalidPath,TResult Function( String field0)?  unsupportedFormat,TResult Function( String field0)?  openFailed,TResult Function( BigInt field0)?  unknownSession,TResult Function( BigInt field0)?  invalidSection,TResult Function( String field0)?  contentFailed,TResult Function( String field0)?  searchFailed,TResult Function( String field0)?  locatorFailed,TResult Function( String field0)?  paginationFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ReaderError_InvalidPath() when invalidPath != null:
return invalidPath(_that.field0);case ReaderError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that.field0);case ReaderError_OpenFailed() when openFailed != null:
return openFailed(_that.field0);case ReaderError_UnknownSession() when unknownSession != null:
return unknownSession(_that.field0);case ReaderError_InvalidSection() when invalidSection != null:
return invalidSection(_that.field0);case ReaderError_ContentFailed() when contentFailed != null:
return contentFailed(_that.field0);case ReaderError_SearchFailed() when searchFailed != null:
return searchFailed(_that.field0);case ReaderError_LocatorFailed() when locatorFailed != null:
return locatorFailed(_that.field0);case ReaderError_PaginationFailed() when paginationFailed != null:
return paginationFailed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String field0)  invalidPath,required TResult Function( String field0)  unsupportedFormat,required TResult Function( String field0)  openFailed,required TResult Function( BigInt field0)  unknownSession,required TResult Function( BigInt field0)  invalidSection,required TResult Function( String field0)  contentFailed,required TResult Function( String field0)  searchFailed,required TResult Function( String field0)  locatorFailed,required TResult Function( String field0)  paginationFailed,}) {final _that = this;
switch (_that) {
case ReaderError_InvalidPath():
return invalidPath(_that.field0);case ReaderError_UnsupportedFormat():
return unsupportedFormat(_that.field0);case ReaderError_OpenFailed():
return openFailed(_that.field0);case ReaderError_UnknownSession():
return unknownSession(_that.field0);case ReaderError_InvalidSection():
return invalidSection(_that.field0);case ReaderError_ContentFailed():
return contentFailed(_that.field0);case ReaderError_SearchFailed():
return searchFailed(_that.field0);case ReaderError_LocatorFailed():
return locatorFailed(_that.field0);case ReaderError_PaginationFailed():
return paginationFailed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String field0)?  invalidPath,TResult? Function( String field0)?  unsupportedFormat,TResult? Function( String field0)?  openFailed,TResult? Function( BigInt field0)?  unknownSession,TResult? Function( BigInt field0)?  invalidSection,TResult? Function( String field0)?  contentFailed,TResult? Function( String field0)?  searchFailed,TResult? Function( String field0)?  locatorFailed,TResult? Function( String field0)?  paginationFailed,}) {final _that = this;
switch (_that) {
case ReaderError_InvalidPath() when invalidPath != null:
return invalidPath(_that.field0);case ReaderError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that.field0);case ReaderError_OpenFailed() when openFailed != null:
return openFailed(_that.field0);case ReaderError_UnknownSession() when unknownSession != null:
return unknownSession(_that.field0);case ReaderError_InvalidSection() when invalidSection != null:
return invalidSection(_that.field0);case ReaderError_ContentFailed() when contentFailed != null:
return contentFailed(_that.field0);case ReaderError_SearchFailed() when searchFailed != null:
return searchFailed(_that.field0);case ReaderError_LocatorFailed() when locatorFailed != null:
return locatorFailed(_that.field0);case ReaderError_PaginationFailed() when paginationFailed != null:
return paginationFailed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ReaderError_InvalidPath extends ReaderError {
  const ReaderError_InvalidPath(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_InvalidPathCopyWith<ReaderError_InvalidPath> get copyWith => _$ReaderError_InvalidPathCopyWithImpl<ReaderError_InvalidPath>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_InvalidPath&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.invalidPath(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_InvalidPathCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_InvalidPathCopyWith(ReaderError_InvalidPath value, $Res Function(ReaderError_InvalidPath) _then) = _$ReaderError_InvalidPathCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ReaderError_InvalidPathCopyWithImpl<$Res>
    implements $ReaderError_InvalidPathCopyWith<$Res> {
  _$ReaderError_InvalidPathCopyWithImpl(this._self, this._then);

  final ReaderError_InvalidPath _self;
  final $Res Function(ReaderError_InvalidPath) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_InvalidPath(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReaderError_UnsupportedFormat extends ReaderError {
  const ReaderError_UnsupportedFormat(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_UnsupportedFormatCopyWith<ReaderError_UnsupportedFormat> get copyWith => _$ReaderError_UnsupportedFormatCopyWithImpl<ReaderError_UnsupportedFormat>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_UnsupportedFormat&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.unsupportedFormat(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_UnsupportedFormatCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_UnsupportedFormatCopyWith(ReaderError_UnsupportedFormat value, $Res Function(ReaderError_UnsupportedFormat) _then) = _$ReaderError_UnsupportedFormatCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ReaderError_UnsupportedFormatCopyWithImpl<$Res>
    implements $ReaderError_UnsupportedFormatCopyWith<$Res> {
  _$ReaderError_UnsupportedFormatCopyWithImpl(this._self, this._then);

  final ReaderError_UnsupportedFormat _self;
  final $Res Function(ReaderError_UnsupportedFormat) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_UnsupportedFormat(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReaderError_OpenFailed extends ReaderError {
  const ReaderError_OpenFailed(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_OpenFailedCopyWith<ReaderError_OpenFailed> get copyWith => _$ReaderError_OpenFailedCopyWithImpl<ReaderError_OpenFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_OpenFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.openFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_OpenFailedCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_OpenFailedCopyWith(ReaderError_OpenFailed value, $Res Function(ReaderError_OpenFailed) _then) = _$ReaderError_OpenFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ReaderError_OpenFailedCopyWithImpl<$Res>
    implements $ReaderError_OpenFailedCopyWith<$Res> {
  _$ReaderError_OpenFailedCopyWithImpl(this._self, this._then);

  final ReaderError_OpenFailed _self;
  final $Res Function(ReaderError_OpenFailed) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_OpenFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReaderError_UnknownSession extends ReaderError {
  const ReaderError_UnknownSession(this.field0): super._();
  

@override final  BigInt field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_UnknownSessionCopyWith<ReaderError_UnknownSession> get copyWith => _$ReaderError_UnknownSessionCopyWithImpl<ReaderError_UnknownSession>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_UnknownSession&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.unknownSession(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_UnknownSessionCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_UnknownSessionCopyWith(ReaderError_UnknownSession value, $Res Function(ReaderError_UnknownSession) _then) = _$ReaderError_UnknownSessionCopyWithImpl;
@useResult
$Res call({
 BigInt field0
});




}
/// @nodoc
class _$ReaderError_UnknownSessionCopyWithImpl<$Res>
    implements $ReaderError_UnknownSessionCopyWith<$Res> {
  _$ReaderError_UnknownSessionCopyWithImpl(this._self, this._then);

  final ReaderError_UnknownSession _self;
  final $Res Function(ReaderError_UnknownSession) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_UnknownSession(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class ReaderError_InvalidSection extends ReaderError {
  const ReaderError_InvalidSection(this.field0): super._();
  

@override final  BigInt field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_InvalidSectionCopyWith<ReaderError_InvalidSection> get copyWith => _$ReaderError_InvalidSectionCopyWithImpl<ReaderError_InvalidSection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_InvalidSection&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.invalidSection(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_InvalidSectionCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_InvalidSectionCopyWith(ReaderError_InvalidSection value, $Res Function(ReaderError_InvalidSection) _then) = _$ReaderError_InvalidSectionCopyWithImpl;
@useResult
$Res call({
 BigInt field0
});




}
/// @nodoc
class _$ReaderError_InvalidSectionCopyWithImpl<$Res>
    implements $ReaderError_InvalidSectionCopyWith<$Res> {
  _$ReaderError_InvalidSectionCopyWithImpl(this._self, this._then);

  final ReaderError_InvalidSection _self;
  final $Res Function(ReaderError_InvalidSection) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_InvalidSection(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class ReaderError_ContentFailed extends ReaderError {
  const ReaderError_ContentFailed(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_ContentFailedCopyWith<ReaderError_ContentFailed> get copyWith => _$ReaderError_ContentFailedCopyWithImpl<ReaderError_ContentFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_ContentFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.contentFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_ContentFailedCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_ContentFailedCopyWith(ReaderError_ContentFailed value, $Res Function(ReaderError_ContentFailed) _then) = _$ReaderError_ContentFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ReaderError_ContentFailedCopyWithImpl<$Res>
    implements $ReaderError_ContentFailedCopyWith<$Res> {
  _$ReaderError_ContentFailedCopyWithImpl(this._self, this._then);

  final ReaderError_ContentFailed _self;
  final $Res Function(ReaderError_ContentFailed) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_ContentFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReaderError_SearchFailed extends ReaderError {
  const ReaderError_SearchFailed(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_SearchFailedCopyWith<ReaderError_SearchFailed> get copyWith => _$ReaderError_SearchFailedCopyWithImpl<ReaderError_SearchFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_SearchFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.searchFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_SearchFailedCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_SearchFailedCopyWith(ReaderError_SearchFailed value, $Res Function(ReaderError_SearchFailed) _then) = _$ReaderError_SearchFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ReaderError_SearchFailedCopyWithImpl<$Res>
    implements $ReaderError_SearchFailedCopyWith<$Res> {
  _$ReaderError_SearchFailedCopyWithImpl(this._self, this._then);

  final ReaderError_SearchFailed _self;
  final $Res Function(ReaderError_SearchFailed) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_SearchFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReaderError_LocatorFailed extends ReaderError {
  const ReaderError_LocatorFailed(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_LocatorFailedCopyWith<ReaderError_LocatorFailed> get copyWith => _$ReaderError_LocatorFailedCopyWithImpl<ReaderError_LocatorFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_LocatorFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.locatorFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_LocatorFailedCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_LocatorFailedCopyWith(ReaderError_LocatorFailed value, $Res Function(ReaderError_LocatorFailed) _then) = _$ReaderError_LocatorFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ReaderError_LocatorFailedCopyWithImpl<$Res>
    implements $ReaderError_LocatorFailedCopyWith<$Res> {
  _$ReaderError_LocatorFailedCopyWithImpl(this._self, this._then);

  final ReaderError_LocatorFailed _self;
  final $Res Function(ReaderError_LocatorFailed) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_LocatorFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReaderError_PaginationFailed extends ReaderError {
  const ReaderError_PaginationFailed(this.field0): super._();
  

@override final  String field0;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReaderError_PaginationFailedCopyWith<ReaderError_PaginationFailed> get copyWith => _$ReaderError_PaginationFailedCopyWithImpl<ReaderError_PaginationFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReaderError_PaginationFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'ReaderError.paginationFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ReaderError_PaginationFailedCopyWith<$Res> implements $ReaderErrorCopyWith<$Res> {
  factory $ReaderError_PaginationFailedCopyWith(ReaderError_PaginationFailed value, $Res Function(ReaderError_PaginationFailed) _then) = _$ReaderError_PaginationFailedCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$ReaderError_PaginationFailedCopyWithImpl<$Res>
    implements $ReaderError_PaginationFailedCopyWith<$Res> {
  _$ReaderError_PaginationFailedCopyWithImpl(this._self, this._then);

  final ReaderError_PaginationFailed _self;
  final $Res Function(ReaderError_PaginationFailed) _then;

/// Create a copy of ReaderError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ReaderError_PaginationFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
