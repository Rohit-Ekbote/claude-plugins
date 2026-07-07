#!/usr/bin/env ruby
# consumer-values.rb — extract every rendered value of an env KEY from a helm
# manifest. Two forms: configmap data (`  KEY: "v"` / `  KEY: v`) and pod env
# (`- name: KEY` immediately followed by `value: "v"`). Values are unquoted.
module ConsumerValues
  def self.unquote(s)
    s = s.strip
    s = s[1..-2] if s.length >= 2 && ((s[0] == '"' && s[-1] == '"') || (s[0] == "'" && s[-1] == "'"))
    s
  end

  def self.values(text, key)
    lines = text.lines
    esc = Regexp.escape(key)
    out = []
    lines.each_with_index do |ln, i|
      # configmap-data form: <ws>KEY: <value>   (the token before ':' is exactly KEY)
      if ln =~ /^\s*#{esc}:\s*(\S.*?)\s*$/
        out << unquote($1)
      # pod-env form: <ws>- name: KEY  then next line  value: <value>
      elsif ln =~ /^\s*-?\s*name:\s*#{esc}\s*$/
        nxt = lines[i + 1]
        out << unquote($1) if nxt && nxt =~ /^\s*value:\s*(\S.*?)\s*$/
      end
    end
    out
  end
end

if __FILE__ == $0
  vals = ConsumerValues.values(File.read(ARGV[0]), ARGV[1])
  puts vals.join("\n")
end
