///| POSIX types and constants

///|
/// POSIX error codes
pub(all) suberror PosixError {
  ENOENT(String) // No such file or directory
  EEXIST(String) // File exists
  ENOTDIR(String) // Not a directory
  EISDIR(String) // Is a directory
  EBADF(String) // Bad file descriptor
  EINVAL(String) // Invalid argument
  EIO(String) // I/O error
  EACCES(String) // Permission denied
  ENOTEMPTY(String) // Directory not empty
} derive(Eq)

///|
pub impl Show for PosixError with output(self, logger) {
  match self {
    ENOENT(s) => {
      logger.write_string("ENOENT(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    EEXIST(s) => {
      logger.write_string("EEXIST(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    ENOTDIR(s) => {
      logger.write_string("ENOTDIR(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    EISDIR(s) => {
      logger.write_string("EISDIR(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    EBADF(s) => {
      logger.write_string("EBADF(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    EINVAL(s) => {
      logger.write_string("EINVAL(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    EIO(s) => {
      logger.write_string("EIO(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    EACCES(s) => {
      logger.write_string("EACCES(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    ENOTEMPTY(s) => {
      logger.write_string("ENOTEMPTY(")
      Show::output(s, logger)
      logger.write_string(")")
    }
  }
}

///|
/// Convert FsError to PosixError
pub fn fs_error_to_posix(err : @fs.FsError) -> PosixError {
  match err {
    @fs.FsError::NotFound(p) => PosixError::ENOENT(p)
    @fs.FsError::AlreadyExists(p) => PosixError::EEXIST(p)
    @fs.FsError::NotADirectory(p) => PosixError::ENOTDIR(p)
    @fs.FsError::NotAFile(p) => PosixError::EISDIR(p)
    @fs.FsError::IsADirectory(p) => PosixError::EISDIR(p)
    @fs.FsError::NotEmpty(p) => PosixError::ENOTEMPTY(p)
    @fs.FsError::PermissionDenied(p) => PosixError::EACCES(p)
    @fs.FsError::InvalidPath(p) => PosixError::EINVAL(p)
    @fs.FsError::IoError(p) => PosixError::EIO(p)
  }
}

///|
/// File descriptor flags
pub(all) struct OpenFlags {
  read : Bool
  write : Bool
  create : Bool
  truncate : Bool
  append : Bool
} derive(Eq)

///|
pub impl Show for OpenFlags with output(self, logger) {
  logger.write_string("{read: ")
  Show::output(self.read, logger)
  logger.write_string(", write: ")
  Show::output(self.write, logger)
  logger.write_string(", create: ")
  Show::output(self.create, logger)
  logger.write_string(", truncate: ")
  Show::output(self.truncate, logger)
  logger.write_string(", append: ")
  Show::output(self.append, logger)
  logger.write_string("}")
}

///|
/// Default: read only
pub fn OpenFlags::default() -> OpenFlags {
  { read: true, write: false, create: false, truncate: false, append: false }
}

///|
/// Read-write
pub fn OpenFlags::read_write() -> OpenFlags {
  { read: true, write: true, create: false, truncate: false, append: false }
}

///|
/// Create or truncate for writing
pub fn OpenFlags::create_write() -> OpenFlags {
  { read: false, write: true, create: true, truncate: true, append: false }
}

///|
/// Standard file descriptors
pub const STDIN_FD : Int = 0

///|
pub const STDOUT_FD : Int = 1

///|
pub const STDERR_FD : Int = 2
