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
    File.foreach(path) do |line|
      # `fail` builtin: preceded by `{{`, `{{-`, or `(` (a template action / pipeline),
      # then any non-quote chars (e.g. ` (printf `), then the first "..." string.
      # Not the bare word "fail" in prose/comments (no preceding `{{`/`(`).
      line.scan(/(?:\{\{-?\s*|\(\s*)fail\b[^"]*"((?:[^"\\]|\\.)*)"/) do |m|
        sig = m[0].gsub(/%[qsdvtf]/, '%').gsub(/\s+/, ' ').strip
        seen[sig] ||= rel unless sig.empty?
      end
    end
  end
end
seen.keys.sort.each { |sig| puts "#{sig}\t#{seen[sig]}" }
