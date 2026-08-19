import Foundation

public enum E01MediaEncodingProfile {
    public static func ffmpegArguments(imagePath: String, moviePath: String) -> [String] {
        [
            "-y", "-nostdin", "-loglevel", "error",
            "-loop", "1", "-framerate", "12", "-i", imagePath,
            "-t", "1", "-vf", "scale=368:368:force_original_aspect_ratio=disable,setsar=1",
            "-c:v", "mpeg4", "-r", "12", "-q:v", "2",
            "-pix_fmt", "yuv420p",
            "-an", "-f", "avi", moviePath,
        ]
    }
}
