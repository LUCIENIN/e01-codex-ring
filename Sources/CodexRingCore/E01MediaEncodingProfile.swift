import Foundation

public enum E01MediaEncodingProfile {
    public static func ffmpegArguments(imagePath: String, moviePath: String) -> [String] {
        [
            "-y", "-nostdin", "-loglevel", "error",
            "-loop", "1", "-framerate", "1", "-i", imagePath,
            "-t", "2", "-vf", "scale=368:368:force_original_aspect_ratio=disable,setsar=1",
            "-c:v", "mjpeg", "-q:v", "5",
            "-pix_fmt", "yuvj420p",
            "-an", "-f", "avi", moviePath,
        ]
    }
}
