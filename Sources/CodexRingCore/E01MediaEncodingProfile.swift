import Foundation

public enum E01MediaEncodingProfile {
    public static func ffmpegArguments(imagePath: String, moviePath: String) -> [String] {
        [
            "-y", "-loglevel", "error",
            "-loop", "1", "-framerate", "12", "-i", imagePath,
            "-t", "2", "-c:v", "mjpeg", "-q:v", "7",
            "-pix_fmt", "yuvj420p",
            "-an", "-f", "avi", moviePath,
        ]
    }
}
