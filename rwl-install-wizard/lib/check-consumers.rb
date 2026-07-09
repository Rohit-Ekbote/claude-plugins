#!/usr/bin/env ruby
# check-consumers.rb <catalog> <answers.yaml> <render.yaml>
# For each answered param that declares consumers, assert its value reaches every
# rendered consumer. Two-part semantics: (a) >=1 of the param's consumer keys must
# occur in the render; (b) every occurrence of every listed key must equal (equals)
# or include (contains) the answer value.
require 'yaml'
require_relative 'consumer-values'
# Read external text (catalog, answers, helm render) as UTF-8 regardless of the
# shell locale. Under LC_ALL=C (common in CI) Ruby's default external encoding is
# US-ASCII, and consumer-values' regex scan then raises "invalid byte sequence"
# on the non-ASCII bytes (em-dashes) helm manifests routinely contain.
Encoding.default_external = Encoding::UTF_8

catalog, answers_file, render_file = ARGV
present_only = (ARGV[3] == "--present-only")
cat = YAML.load_file(catalog)

# param id -> {"equals"=>[...], "contains"=>[...]}
consumers = {}
collect = lambda do |pl|
  (pl || []).each { |p| consumers[p["id"]] = p["consumers"] if p.is_a?(Hash) && p["consumers"] }
end
(cat["axes"] || []).each { |a| collect.call(a["params"]); (a["options"] || []).each { |o| collect.call(o["params"]) } }

# flatten answers: axis -> {option, <pid>: <val>} into pid -> val
answers = {}
(YAML.load_file(answers_file)["answers"] || {}).each do |_axis, m|
  next unless m.is_a?(Hash)
  m.each { |k, v| answers[k] = v unless k == "option" }
end

render = File.read(render_file)
fails = 0
answers.each do |pid, val|
  c = consumers[pid]
  next unless c
  val = val.to_s
  total = 0
  bad = []
  (c["equals"] || []).each do |key|
    vs = ConsumerValues.values(render, key)
    total += vs.size
    vs.each { |rv| bad << "#{key}=#{rv} (!= #{val})" unless rv == val }
  end
  (c["contains"] || []).each do |key|
    vs = ConsumerValues.values(render, key)
    total += vs.size
    vs.each { |rv| bad << "#{key}=#{rv} (!~ #{val})" unless rv.include?(val) }
  end
  keys = ((c["equals"] || []) + (c["contains"] || [])).join(",")
  if total == 0
    next if present_only
    puts "  FAIL: #{pid}: value #{val} reached NO consumer [#{keys}]"; fails += 1
  elsif !bad.empty?
    puts "  FAIL: #{pid}: #{bad.join('; ')}"; fails += 1
  else
    puts "  PASS: #{pid} -> [#{keys}] all resolve to #{val}"
  end
end
exit(fails == 0 ? 0 : 1)
