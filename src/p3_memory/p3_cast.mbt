///|
fn p3_duration_from_u64(v : UInt64) -> @p3.ClocksTypesDuration = "%identity"

///|
fn p3_mark_from_u64(v : UInt64) -> @p3.ClocksMonotonicClockMark = "%identity"

///|
fn p3_mark_to_u64(v : @p3.ClocksMonotonicClockMark) -> UInt64 = "%identity"

///|
fn p3_filesize_from_u64(v : UInt64) -> @p3.FilesystemTypesFilesize = "%identity"

///|
fn p3_filesize_to_u64(v : @p3.FilesystemTypesFilesize) -> UInt64 = "%identity"

///|
fn p3_descriptor_flags_from_uint(
  v : UInt,
) -> @p3.FilesystemTypesDescriptorFlags = "%identity"

///|
fn p3_path_flags_from_uint(v : UInt) -> @p3.FilesystemTypesPathFlags = "%identity"

///|
fn p3_link_count_from_u64(v : UInt64) -> @p3.FilesystemTypesLinkCount = "%identity"

///|
fn p3_field_name_from_string(v : String) -> @p3.HttpTypesFieldName = "%identity"

///|
fn p3_field_name_to_string(v : @p3.HttpTypesFieldName) -> String = "%identity"

///|
fn p3_field_value_from_bytes(v : Bytes) -> @p3.HttpTypesFieldValue = "%identity"

///|
fn p3_field_value_to_bytes(v : @p3.HttpTypesFieldValue) -> Bytes = "%identity"

///|
fn p3_headers_from_int(v : Int) -> @p3.HttpTypesHeaders = "%identity"

///|
fn p3_headers_to_int(v : @p3.HttpTypesHeaders) -> Int = "%identity"

///|
fn p3_status_code_from_int(v : Int) -> @p3.HttpTypesStatusCode = "%identity"

///|
fn p3_status_code_to_int(v : @p3.HttpTypesStatusCode) -> Int = "%identity"
