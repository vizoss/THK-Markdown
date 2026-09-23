package com.thk.mdview

import android.util.Base64

/** Mirrors THKMarkdownExtensions.swift. Protected code/URLs never acquire P3 syntax. */
internal object MarkdownExtensions {
    // Fixed patterns are compiled once, never in the per-line parsing loops.
    private val pattern0 = Regex("^ {0,3}\\[(?!\\^)[^\\]]+\\]:")
    private val pattern1 = Regex("^ {0,3}\\[\\^([^\\]\\s]+)\\]:[ \\t]*(.*)$")
    private val pattern2 = Regex("^(?: {0,3}>[ ]?)*")
    private val pattern3 = Regex("^ {0,3}(`{3,}|~{3,})[ \\t]*$")
    private val pattern4 = Regex("^ {0,3}(`{3,}|~{3,})(.*)$")
    fun prepare(source: String): String {
        val (protected, literals) = protectCode(source.replace("\r\n", "\n"))
        val lines = protected.split('\n')
        val definitions = linkedMapOf<String, String>()
        val body = mutableListOf<String>()
        val fence = Fence()
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            if (fence.protect(line) || line.startsWith("    ") || line.startsWith("\t") || pattern0.containsMatchIn(line)) {
                body += line; i++; continue
            }
            val match = pattern1.matchEntire(line)
            if (match != null) {
                var definition = match.groupValues[2]
                i++
                while (i < lines.size) {
                    if (lines[i].startsWith("    ")) { definition += "\n" + lines[i].drop(4); i++ }
                    else if (lines[i].isEmpty() && i + 1 < lines.size && lines[i + 1].startsWith("    ")) { definition += "\n"; i++ }
                    else break
                }
                definitions.putIfAbsent(match.groupValues[1], definition)
                body += ""
            } else { body += line; i++ }
        }
        val order = mutableListOf<String>()
        val output = mutableListOf<String>()
        fence.active = null
        i = 0
        while (i < body.size) {
            val line = body[i]
            if (fence.protect(line) || line.startsWith("    ") || line.startsWith("\t") || pattern0.containsMatchIn(line)) {
                output += line; i++; continue
            }
            val trim = line.trim()
            if (trim == "$$" || trim == "\\[") {
                val close = if (trim == "$$") "$$" else "\\]"
                val end = (i + 1 until body.size).firstOrNull { body[it].trim() == close }
                if (end != null) {
                    output += "\n" + mathImage(body.subList(i + 1, end).joinToString("\n"), true, literals) + "\n"
                    i = end + 1; continue
                }
                output.addAll(body.subList(i, body.size)); break
            }
            output += inline(line, definitions, order, literals)
            i++
        }
        if (order.isNotEmpty()) {
            output += "\n---\n"
            order.forEachIndexed { index, label ->
                val value = inline(definitions[label].orEmpty(), emptyMap(), mutableListOf(), literals)
                output += "${index + 1}. " + value.replace("\n", "\n    ")
            }
        }
        var result = output.joinToString("\n")
        literals.forEach { (token, literal) -> result = result.replace(token, literal) }
        return result
    }

    private fun protectCode(source: String): Pair<String, List<Pair<String, String>>> {
        val fence = Fence()
        val pending = mutableListOf<String>()
        val parts = mutableListOf<String>()
        val literals = mutableListOf<Pair<String, String>>()
        fun flush() {
            if (pending.isEmpty()) return
            val value = protectSpans(pending.joinToString("\n"))
            parts += value.first; literals += value.second; pending.clear()
        }
        source.split('\n').forEach { line ->
            if (fence.protect(line)) { flush(); parts += line } else pending += line
        }
        flush()
        return parts.joinToString("\n") to literals
    }

    private fun protectSpans(source: String): Pair<String, List<Pair<String, String>>> {
        val nonce = "THKOPAQUE" + java.util.UUID.randomUUID().toString().replace("-", "")
        val saved = mutableListOf<Pair<String, String>>()
        val out = StringBuilder()
        var i = 0
        while (i < source.length) {
            if (source[i] == '\\' && i + 1 < source.length) { out.append(source, i, i + 2); i += 2; continue }
            if (source[i] == '`') {
                var end = i + 1
                while (end < source.length && source[end] == '`') end++
                var scan = end
                var close = -1
                while (scan < source.length) {
                    if (source[scan] != '`') { scan++; continue }
                    val begin = scan
                    while (scan < source.length && source[scan] == '`') scan++
                    if (scan - begin == end - i) { close = scan; break }
                }
                if (close >= 0) {
                    val literal = source.substring(i, close)
                    if (end - i >= 3 || !literal.contains("\n\n")) {
                        val token = nonce + "N${saved.size}END"
                        saved += token to literal; out.append(token); i = close; continue
                    }
                }
                out.append(source, i, end); i = end; continue
            }
            out.append(source[i]); i++
        }
        return out.toString() to saved
    }

    private class Fence {
        var active: Pair<Char, Int>? = null
        fun protect(line: String): Boolean {
            val probe = line.replace(pattern2, "")
            active?.let { (character, length) ->
                val close = pattern3.matchEntire(probe)
                if (close != null && close.groupValues[1][0] == character && close.groupValues[1].length >= length) active = null
                return true
            }
            val open = pattern4.matchEntire(probe) ?: return false
            active = open.groupValues[1][0] to open.groupValues[1].length
            return true
        }
    }

    private fun inline(line: String, definitions: Map<String, String>, order: MutableList<String>, literals: List<Pair<String, String>> = emptyList()): String {
        val out = StringBuilder()
        var i = 0
        while (i < line.length) {
            val ch = line[i]
            if (ch == '`') {
                var end = i + 1
                while (end < line.length && line[end] == '`') end++
                val count = end - i
                var scan = end
                var close = -1
                while (scan < line.length) {
                    if (line[scan] != '`') { scan++; continue }
                    val begin = scan
                    while (scan < line.length && line[scan] == '`') scan++
                    if (scan - begin == count) { close = scan; break }
                }
                if (close >= 0) end = close
                out.append(line, i, end); i = end; continue
            }
            if (ch == '\\') {
                if (line.startsWith("\\(", i)) {
                    val end = find(line, i + 2, "\\)")
                    if (end >= 0) { out.append(mathImage(line.substring(i + 2, end), false, literals)); i = end + 2; continue }
                }
                val end = minOf(i + 2, line.length)
                out.append(line, i, end); i = end; continue
            }
            if (ch == '<') {
                val end = line.indexOf('>', i + 1)
                if (end >= 0) { out.append(line, i, end + 1); i = end + 1; continue }
            }
            if (line.startsWith("](", i)) {
                var end = i + 2
                var depth = 1
                while (end < line.length && depth > 0) {
                    if (line[end] == '\\') { end = minOf(end + 2, line.length); continue }
                    if (line[end] == '(') depth++
                    if (line[end] == ')') depth--
                    end++
                }
                out.append(line, i, end); i = end; continue
            }
            if (line.startsWith("[^", i)) {
                val end = line.indexOf(']', i + 2)
                if (end >= 0) {
                    val label = line.substring(i + 2, end)
                    if (definitions.containsKey(label)) {
                        if (label !in order) order += label
                        out.append("[${order.indexOf(label) + 1}](thk-footnote://reference)"); i = end + 1; continue
                    }
                }
            }
            if (ch == '$' && i + 1 < line.length && !line[i + 1].isWhitespace()) {
                val count = if (line[i + 1] == '$') 2 else 1
                val end = find(line, i + count, "$".repeat(count))
                if (end > i + count && !line[end - 1].isWhitespace() &&
                    !(end + count < line.length && line[end + count].isDigit())) {
                    out.append(mathImage(line.substring(i + count, end), count == 2, literals)); i = end + count; continue
                }
            }
            out.append(ch); i++
        }
        return out.toString()
    }

    private fun find(line: String, start: Int, delimiter: String): Int {
        var i = start
        while (i + delimiter.length <= line.length) {
            if (line[i] == '\\' && delimiter[0] != '\\') { i += 2; continue }
            if (line.startsWith(delimiter, i)) return i
            i++
        }
        return -1
    }

    private fun mathImage(input: String, display: Boolean, literals: List<Pair<String, String>> = emptyList()): String {
        var tex = input
        literals.forEach { (token, literal) -> tex = tex.replace(token, literal) }
        if (tex.isBlank() || tex.toByteArray(Charsets.UTF_8).size > 8192) return tex
        val encoded = Base64.encodeToString(tex.toByteArray(Charsets.UTF_8), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        return "![formula](thk-math://${if (display) "display" else "inline"}/$encoded)"
    }
}
