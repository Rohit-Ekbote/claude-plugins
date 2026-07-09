#!/usr/bin/env ruby
# assemble-report.rb <findings.tsv> <out-dir>
require 'json'
# Read external text as UTF-8 regardless of the shell locale. Under LC_ALL=C
# (common in CI) Ruby's default external encoding is US-ASCII, and split/regex
# then raise "invalid byte sequence" on the em-dashes that chart fail messages
# and the detector's own finding details contain — leaving no report written.
Encoding.default_external = Encoding::UTF_8
tsv, outdir = ARGV
cols = %w[bucket kind option detail evidence current chart]
auto = []; decide = []
File.readlines(tsv).each do |line|
  f = line.chomp.split("\t", -1)
  next if f.length < 7
  row = Hash[cols.zip(f)]
  (row["bucket"] == "auto" ? auto : decide) << row.reject { |k, _| k == "bucket" }
end
File.write(File.join(outdir, "drift-report.json"),
           JSON.pretty_generate("autoFixable" => auto, "needsDecision" => decide))
md = +"# Catalog drift report\n\n"
render = lambda do |title, rows|
  md << "## #{title} (#{rows.length})\n\n"
  if rows.empty? then md << "_none_\n\n"
  else rows.each { |r| md << "- **#{r['kind']}** #{r['option'].empty? ? '' : "[#{r['option']}] "}— #{r['detail']}" \
                          "#{r['current'].to_s.empty? ? '' : " (`#{r['current']}` → `#{r['chart']}`)"}" \
                          "#{r['evidence'].to_s.empty? ? '' : "  \n  _#{r['evidence']}_"}\n" }
       md << "\n"
  end
end
render.call("Auto-fixable", auto)
render.call("Needs decision", decide)
File.write(File.join(outdir, "drift-report.md"), md)
