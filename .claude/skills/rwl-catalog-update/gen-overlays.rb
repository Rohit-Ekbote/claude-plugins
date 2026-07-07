#!/usr/bin/env ruby
# gen-overlays.rb <catalog.yaml> <out-dir> <option-id>
# Render ONE catalog option's emits to an overlay file, substituting each of the
# option's params (axis-level + option-level) with a render-valid DUMMY value.
# Dummies need only make `helm template` succeed — never semantically correct.
require 'yaml'
catalog, outdir, want = ARGV
abort "usage: gen-overlays.rb <catalog> <out-dir> <option-id>" unless want

def snake(id); id.gsub(/([a-z0-9])([A-Z])/, '\1_\2').upcase; end

def dummy(id)
  case id
  when /Url$/          then "https://dummy.example/v1"
  when /Host$/, /Endpoint$/ then "mirror.example"
  when /Secret/        then "dummy-secret"
  when /Class$/        then "dummy-sc"
  when /Uid$/, /Gid$/, /Dimension$/, /Port$/ then "1000"
  when "releaseName"   then "rw"          # must match the detector's helm release name
  when "domain"        then "ex.example.com"
  when "bundleFile"    then "ca.crt"
  else "dummy-#{id.gsub(/([A-Z])/){ "-#{$1.downcase}" }}"
  end
end

def subst(o, m)
  case o
  when String then r = o; m.each { |k, v| r = r.gsub("<#{k}>", v.to_s) }; r
  when Array  then o.map { |e| subst(e, m) }
  when Hash   then o.each_with_object({}) { |(k, v), h| h[subst(k, m)] = subst(v, m) }
  else o
  end
end

cat = YAML.load_file(catalog)
cat["axes"].each do |axis|
  (axis["options"] || []).each do |opt|
    next unless opt["id"] == want
    ov = opt["overlay"]; em = opt["emits"]
    next if ov.nil? || em.nil? || em == {}
    pids = []
    (axis["params"] || []).each { |p| pids << p["id"] }
    (opt["params"]  || []).each { |p| pids << p["id"] }
    pmap = {}; pids.each { |id| pmap[snake(id)] = dummy(id) }
    data = subst(Marshal.load(Marshal.dump(em)), pmap)
    File.write(File.join(outdir, ov), data.to_yaml)
    puts ov
    if ARGV[3] == "--answers"
      ans = { "option" => want }
      pids.each { |pid| ans[pid] = dummy(pid) }
      File.write(File.join(outdir, "answers.yaml"), { "answers" => { "x" => ans } }.to_yaml)
    end
  end
end
