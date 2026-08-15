///| Virtual filesystem types

///|
/// File system errors
pub(all) suberror FsError {
  NotFound(String)
  AlreadyExists(String)
  NotADirectory(String)
  NotAFile(String)
  IsADirectory(String)
  NotEmpty(String)
  PermissionDenied(String)
  InvalidPath(String)
  IoError(String)
} derive(Eq)

///|
pub impl Show for FsError with output(self, logger) {
  match self {
    NotFound(s) => {
      logger.write_string("NotFound(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    AlreadyExists(s) => {
      logger.write_string("AlreadyExists(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    NotADirectory(s) => {
      logger.write_string("NotADirectory(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    NotAFile(s) => {
      logger.write_string("NotAFile(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    IsADirectory(s) => {
      logger.write_string("IsADirectory(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    NotEmpty(s) => {
      logger.write_string("NotEmpty(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    PermissionDenied(s) => {
      logger.write_string("PermissionDenied(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    InvalidPath(s) => {
      logger.write_string("InvalidPath(")
      Show::output(s, logger)
      logger.write_string(")")
    }
    IoError(s) => {
      logger.write_string("IoError(")
      Show::output(s, logger)
      logger.write_string(")")
    }
  }
}

///|
/// File type enumeration
pub(all) enum FileType {
  File
  Directory
  Symlink
} derive(Eq)

///|
pub impl Show for FileType with output(self, logger) {
  match self {
    File => logger.write_string("File")
    Directory => logger.write_string("Directory")
    Symlink => logger.write_string("Symlink")
  }
}

///|
/// File metadata
pub(all) struct FileStat {
  file_type : FileType
  size : Int
  // Future: mtime, atime, ctime, mode, etc.
} derive(Eq)

///|
pub impl Show for FileStat with output(self, logger) {
  logger.write_string("{file_type: ")
  Show::output(self.file_type, logger)
  logger.write_string(", size: ")
  Show::output(self.size, logger)
  logger.write_string("}")
}

///|
/// Default file stat
pub fn FileStat::default() -> FileStat {
  { file_type: FileType::File, size: 0 }
}

///|
/// Directory entry
pub(all) struct DirEntry {
  name : String
  file_type : FileType
} derive(Eq)

///|
pub impl Show for DirEntry with output(self, logger) {
  logger.write_string("{name: ")
  Show::output(self.name, logger)
  logger.write_string(", file_type: ")
  Show::output(self.file_type, logger)
  logger.write_string("}")
}
