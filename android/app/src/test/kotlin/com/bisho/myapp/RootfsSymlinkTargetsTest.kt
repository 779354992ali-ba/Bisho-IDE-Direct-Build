package com.bisho.myapp

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootfsSymlinkTargetsTest {
    @Test
    fun x11DotTargetIsStoredAsDotAndResolvesToUsrBin() = withRoot { root ->
        val bin = Files.createDirectories(root.resolve("usr/bin"))
        val link = bin.resolve("X11")

        val resolved = RootfsSymlinkTargets.resolveGuestTarget(root, link, ".")
        val stored = RootfsSymlinkTargets.targetForCreation(link, resolved, ".")

        assertEquals(bin, resolved)
        assertEquals(Paths.get("."), stored)
        Files.createSymbolicLink(link, stored)
        assertEquals(Paths.get("."), Files.readSymbolicLink(link))
        assertTrue(Files.isSameFile(link, bin))
    }

    @Test
    fun relativeTarTargetKeepsItsOriginalSpelling() = withRoot { root ->
        val link = root.resolve("usr/bin/tool")
        val raw = "./../lib/./tool.so"

        val resolved = RootfsSymlinkTargets.resolveGuestTarget(root, link, raw)
        val stored = RootfsSymlinkTargets.targetForCreation(link, resolved, raw)

        assertEquals(root.resolve("usr/lib/tool.so").normalize(), resolved)
        assertEquals(Paths.get(raw), stored)
    }

    @Test
    fun absoluteGuestTargetIsTranslatedInsideRootfs() = withRoot { root ->
        val link = root.resolve("usr/bin/X11")
        val resolved = RootfsSymlinkTargets.resolveGuestTarget(root, link, "/usr/bin")

        assertEquals(root.resolve("usr/bin"), resolved)
        assertEquals(Paths.get("."), RootfsSymlinkTargets.targetForCreation(link, resolved, "/usr/bin"))
    }

    @Test
    fun traversalOutsideRootfsIsRejected() = withRoot { root ->
        val link = root.resolve("usr/bin/escape")
        try {
            RootfsSymlinkTargets.resolveGuestTarget(root, link, "../../../../../../etc/passwd")
            throw AssertionError("Expected rootfs traversal to be rejected")
        } catch (_: SecurityException) {
            // Expected.
        }
    }

    @Test
    fun movedSymlinkUsesDotWhenItsNewTargetIsItsParent() = withRoot { root ->
        val newLink = root.resolve("usr/bin/X11")
        val target = root.resolve("usr/bin")

        assertEquals(Paths.get("."), RootfsSymlinkTargets.relativeTarget(newLink, target))
    }

    @Test
    fun symlinkPathOutsideRootfsIsRejected() = withRoot { root ->
        val outside = root.parent.resolve("outside-link")
        try {
            RootfsSymlinkTargets.resolveGuestTarget(root, outside, ".")
            throw AssertionError("Expected an outside link path to be rejected")
        } catch (_: SecurityException) {
            // Expected.
        }
    }

    private fun withRoot(block: (Path) -> Unit) {
        val root = Files.createTempDirectory("bisho-rootfs-link-test")
        try {
            block(root)
        } finally {
            Files.walk(root).use { paths ->
                paths.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) }
            }
        }
    }
}
