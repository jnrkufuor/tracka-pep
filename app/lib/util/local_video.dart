// Plays a video the player just picked, before it's uploaded.
//
// On phones the picked file has a path on disk (dart:io File); on the web it's a
// blob: URL. dart:io doesn't exist on the web, so we pick the implementation at
// compile time with a CONDITIONAL IMPORT: the web build never sees dart:io.
export 'local_video_web.dart' if (dart.library.io) 'local_video_io.dart';
