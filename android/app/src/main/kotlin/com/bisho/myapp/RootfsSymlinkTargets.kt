package com.bisho.myapp

import java.nio.file.Path
import java.nio.file.Paths

/**
 * Converts TAR symlink targets using Linux guest-root semantics while keeping
 * relative link text intact when it is written to the host filesystem.
 *
 * Relative TAR targets are meaningful from the link's parent and must not be
 * rewritten with Path.relativize(): when target == parent that produces an
 * empty Path, which Files.createSymbolicLink rejects.
 */
internal object RootfsSymlinkTargets {
    fun resolveGuestTarget(rootPath: Path, linkPath: Path, rawTarget: String): Path {
        if (rawTarget.isBlank() || rawTarget.indexOf('\u0000') >= 0) {
            throw SecurityException("TAR symlink target is empty or invalid.")
        }
        val root = rootPath.toAbsolutePath().normalize()
        val link = linkPath.toAbsolutePath().normalize()
        if (!link.startsWith(root) || link == root || link.parent == null) {
            throw SecurityException("TAR symlink path is outside the rootfs.")
        }

        // Absolute TAR paths are absolute inside the Linux guest, never on Android.
        val candidate = if (rawTarget.startsWith("/")) {
            root.resolve(rawTarget.trimStart('/'))
        } else {
            link.parent.resolve(rawTarget)
        }
        val resolved = candidate.normalize()
        if (!resolved.startsWith(root)) {
            throw SecurityException("TAR symlink target escapes the rootfs.")
        }
        return resolved
    }

    /**
     * Relative targets retain their exact TAR spelling (including "." and "./").
     * Absolute guest targets are rewritten relative to the host link parent.
     */
    fun targetForCreation(linkPath: Path, resolvedTarget: Path, rawTarget: String): Path {
        if (rawTarget.startsWith("/")) {
            return relativeTarget(linkPath, resolvedTarget)
        }
        if (rawTarget.isBlank() || rawTarget.indexOf('\u0000') >= 0) {
            throw SecurityException("TAR symlink target is empty or invalid.")
        }
        return Paths.get(rawTarget)
    }

    /** Builds a relative target after a symlink is moved during directory merging. */
    fun relativeTarget(linkPath: Path, resolvedTarget: Path): Path {
        val parent = linkPath.toAbsolutePath().normalize().parent
            ?: throw SecurityException("TAR symlink has no parent directory.")
        val target = resolvedTarget.toAbsolutePath().normalize()
        val relative = parent.relativize(target)
        return if (relative.toString().isEmpty()) Paths.get(".") else relative
    }
}
