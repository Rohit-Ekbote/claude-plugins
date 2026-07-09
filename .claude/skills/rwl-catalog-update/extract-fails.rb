#!/usr/bin/env ruby
# extract-fails.rb <templates-dir>
# Scan Helm template files under <dir> for Go-template `fail` BUILTIN calls and
# print one line per UNIQUE normalized message signature: "<signature>\t<relfile>",
# sorted by signature.
#
# Signature = the first double-quoted string after `fail` (covers `fail "MSG"` and
# `fail (printf "FMT" ...)`), with printf verbs (%q %s %d %v %t %f) collapsed to `%`
# and every run of whitespace collapsed to a single space, trimmed. Rewording a
# message changes the signature — the accepted identity tradeoff (see design spec).
require 'find'
dir = ARGV[0]
abort "usage: extract-fails.rb <templates-dir>" unless dir
seen = {}   # signature -> first relative file where seen
if File.directory?(dir)
  Find.find(dir) do |path|
    next unless File.file?(path) && path =~ /\.(ya?ml|tpl)\z/
    rel = path.sub(/\A#{Regexp.escape(dir)}\/?/, '')
    # Read as UTF-8 regardless of the shell locale: under LC_ALL=C (common in CI)
    # Ruby's default external encoding is US-ASCII, and `scan` then raises
    # "invalid byte sequence" on the first non-ASCII byte (a curly quote in a
    # comment is enough) — crashing before any output, which would make check_fails
    # silently detect nothing. `scrub` drops any genuinely-malformed byte.
    File.foreach(path, encoding: 'UTF-8') do |raw|
      line = raw.scrub
      # `fail` builtin: preceded by `{{`, `{{-`, or `(` (a template action / pipeline),
      # then any non-quote chars (e.g. ` (printf `), then the first "..." string.
      # Not the bare word "fail" in prose/comments (no preceding `{{`/`(`).
      # Known limitation: matching is per-line and double-quote-string-only, so a
      # `fail` whose message spans multiple lines, uses a backtick raw string, or
      # is a variable (e.g. `fail $msg`) is not captured (none exist in 0.2.59).
      line.scan(/(?:\{\{-?\s*|\(\s*)fail\b[^"]*"((?:[^"\\]|\\.)*)"/) do |m|
        sig = m[0].gsub(/%[qsdvtf]/, '%').gsub(/\s+/, ' ').strip
        seen[sig] ||= rel unless sig.empty?
      end
    end
  end
end
seen.keys.sort.each { |sig| puts "#{sig}\t#{seen[sig]}" }
